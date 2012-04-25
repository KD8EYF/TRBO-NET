
package TRBO::TMS;

=head1 NAME

TRBO::TMS - trbo text message parser.

=head1 FUNCTIONS

=cut

use strict;
use warnings;

use Data::Dumper;
use Encode;

use TRBO::DupeCache;
use TRBO::Common;
our @ISA = ('TRBO::Common');

# this ain't right, but it's start
my $enc_utf16 = find_encoding("ucs-2") || die "Could not load encoding utf16";
my $enc_utf8 = find_encoding("UTF-8") || die "Could not load encoding UTF-8";

=over

=item init()

Init.

=back

=cut

sub init($)
{
    my($self) = @_;
    
    $self->{'msgid_cache'} = new TRBO::DupeCache();
    $self->{'msgid_cache'}->init();
}

=over

=item tms_decode($data)

Decodes text message packet

=back

=cut

sub tms_decode($$$)
{
    my($self, $rh, $data) = @_;
    
    $self->_rx_accounting($data);
    
    my $plen = length($data);
    
    if ($plen < 2) {
        return $self->_fail($rh, 'plen_short');
    }
    
    my $dlen = unpack('n', substr($data, 0, 2));
    
    $self->_debug("dlen $dlen plen $plen");
    
    if ($dlen != $plen - 2) {
        return $self->_fail($rh, 'plen_mismatch');
    }
    
    $rh->{'class'} = 'tms';
    
    my $op_a = unpack('C', substr($data, 0, 1));
    my $op_b = unpack('C', substr($data, 2, 1));
    
    # ack: 0003bf00 01
    if ($op_a == 0x00) {
        if ($op_b == 0xbf || $op_b == 0x9f) {
            return $self->_decode_ack($rh, $data);
        } else {
            return $self->_decode_msg($rh, $data);
        }
    }
    
    return $self->_fail($rh, 'unknown');
}

sub _decode_msg($$$)
{
    my($self, $rh, $data) = @_;
    
    my $op_b = unpack('C', substr($data, 2, 1));
    
    # header length... just guess, but it seems to match?
    my $hdr_len = (($op_b & 0x80) >> 7) | (($op_b & 0x40) >> 5) | (($op_b & 0x20) >> 3);
    
    $self->_debug("tms op_b " . sprintf('%02x', $op_b) . " hdr_len $hdr_len");
    
    # Msgid is 5 bits, 0 to 0x1f. Found out hard way - transmitted
    # message to radio with msgid 0x20 (32) and it ACKed msg 0. So I
    # retransmitted. And retransmitted. And retransmitted. User found this
    # annoying.
    my $msgid = unpack('C', substr($data, 4, 1)) & 0x1f;
    my $msgdata = substr($data, $hdr_len + 3);
    $self->_debug("msgdata: " . TRBO::Common::_hex_dump($msgdata));
    
    # Message appears to be in 16-bit character encoding. For ASCII messages,
    # every second byte is NULL.
    $msgdata =~ s/\0//g;
    
    # blah, does not work? bytes are wrong way around?
    #my $msg_int = $enc_utf16->decode($msgdata, Encode::FB_QUIET);
    #my $msg_utf8 = $enc_utf8->encode($msgdata);
    
    # Check that message is not duplicate of previously received one
    my $dupekey = $rh->{'src_id'} . '.' . $msgid;
    if ($self->{'msgid_cache'}->add($dupekey)) {
        $self->_debug("received duplicate msg $msgid from " . $rh->{'src_id'});
        $rh->{'msg'} = 'msg_dupe';
        $rh->{'msgid'} = $msgid;
        return 1;
    }
    
    $rh->{'msg'} = 'msg';
    $rh->{'msgid'} = $msgid;
    $rh->{'text'} = $msgdata;
    $rh->{'op_b'} = $op_b;
    
    $self->_info($rh->{'src_id'} . ": RX MSG $msgid: '" . $msgdata . "'");
    
    # should reply with 00 03 bf 00 01
    # where last byte is messageid
    
    return 1;
}

=over

=item ack_msg($msghash)

Sends ACK to received message. Pass in received message.

=back

=cut

sub ack_msg($$)
{
    my($self, $rh) = @_;
    
    $self->_debug("sending msg ack to " . $rh->{'src_id'} . " msgid " . $rh->{'msgid'});
    
    # op byte seems to vary, if mg had 0xC0 we should hav 0xbF.
    # if it had 0xe0 we should have 0x9f.
    $self->_send($rh->{'src_id'},
        pack('C*', ($rh->{'op_b'} == 0xc0) ? 0xbf : 0x9f, 0x00, $rh->{'msgid'}),
        pack('C', 0x00));
}

sub _decode_ack($$$)
{
    my($self, $rh, $data) = @_;
    
    my $msgid = unpack('C', substr($data, 4));
    $self->_info($rh->{'src_id'} . ": RX MSG ack for $msgid");
    
    $self->dequeue_msg($rh->{'src_id'}, $msgid);
}

=over

=item dequeue_msg($id, $msgid)

Drop message from transmit queue of destination radio ID.

=back

=cut

sub dequeue_msg($$$)
{
    my($self, $id, $msgid_del) = @_;
    
    my $q = $self->{'msgq'}->{$id};
    if ($#{ $q } < 0) {
        $self->_debug("dequeue_msg: queue empty");
        return;
    }
    
    for (my $idx = 0; $idx <= $#{ $q }; $idx++) {
        my $msg = @{ $q }[$idx];
        if ($msg->{'msgid'} == $msgid_del) {
            $self->_debug("dequeue_msg: found $msgid_del, deleting");
            splice(@{ $q }, $idx, 1);
            return;
        }
    }
}

=over

=item queue_msg($id, $msgtext)

Queue text message to be transmitted to radio ID.

=back

=cut

sub queue_msg($$$)
{
    my($self, $id, $msg) = @_;
    
    if (!defined($self->{'msgq'})) {
        $self->{'msgq'} = {};
    }
    
    if (!defined($self->{'msgq'}->{$id})) {
        $self->{'msgq'}->{$id} = [];
    }
    
    if (!defined $self->{'msgid'}) {
        $self->{'msgid'} = 30;
    }
    
    # msgid is 5 bits, 0 to 31.
    $self->{'msgid'} += 1;
    $self->{'msgid'} = 0 if ($self->{'msgid'} > 31);
    
    $self->_info($id . ": TX MSG queued " . $self->{'msgid'} . ": $msg");
    
    push  @{ $self->{'msgq'}->{$id} }, { 
        'init_t' => time(),
        'next_tx_t' => time(),
        'retry_int' => $self->{'config'}->{'tms_init_retry_interval'},
        'tries' => 0,
        'msgid' => $self->{'msgid'},
        'text' => $msg
    };
    
    $self->queue_run();
}

=over

=item queue_run()

Check queue and transmit any messages which should be
transmitted

=back

=cut

sub queue_run($)
{
    my($self) = @_;
    
    #$self->_debug("queue_run");
    
    foreach my $id (keys %{ $self->{'msgq'} }) {
        #$self->_debug("queue checking id $id:");
        my $q = $self->{'msgq'}->{$id};
        if ($#{ $q } < 0) {
            $self->_debug("id $id: queue empty");
            delete $self->{'msgq'}->{$id};
            next;
        }
        my $first = @{ $q }[0];
        #$self->_debug("first in q: " . Dumper($first));
        if ($first->{'next_tx_t'} <= time()) {
            $self->_debug("tx timer passed for dst $id msgid " . $first->{'msgid'});
            $first->{'next_tx_t'} = time() + $first->{'retry_int'};
            $first->{'retry_int'} *= 2;
            if ($first->{'retry_int'} > $self->{'config'}->{'tms_max_retry_interval'}) {
                $first->{'retry_int'} = $self->{'config'}->{'tms_max_retry_interval'};
            }
            $first->{'tries'} += 1;
            if ($first->{'init_t'} < time() - $self->{'config'}->{'tms_queue_max_age'}) {
                $self->_info($id . ": TX MSG timed out " . $first->{'msgid'});
                shift @{ $q };
            }
            $self->_queue_tx($id, $first);
        }
    }
    
    $self->{'msgid_cache'}->scan();
}

sub _queue_tx($$$)
{
    my($self, $id, $m) = @_;
    
    $self->_debug("_queue_tx to $id: " . Dumper($m));
    
    # This is not right, but ok for ASCII.
    # message does uses two bytes per character, so I guess some form
    # of Unicode.
    my $msg_enc = $m->{'text'};
    $msg_enc =~ s/(.)/$1\000/g;
    
    $self->_send($id, pack('C*', 0xc0, 0x00, 0x80 | $m->{'msgid'}, 0x04) . $msg_enc, pack('C', 0x00));
}

sub _pack($$;$)
{
    my($self, $data, $prefix) = @_;
    
    my $out = pack('C', length($data)) . $data;
    
    if (defined $prefix) {
        $out = $prefix . $out;
    }
    
    return $out;
}


1;

