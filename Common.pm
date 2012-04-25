
package TRBO::Common;

=head1 NAME

TRBO::Common - Common utilities used by other modules

=head1 ABSTRACT

TRBO::NET - A trbo parser

=head1 FUNCTIONS

=cut

our $VERSION = "1.2";

use strict;
use warnings;

use Socket;

sub _hex_dump($)
{
    my($s) = @_;
    
    my $out = '';
    
    my $l = length($s);
    
    my $bytes_in_a_chunk = 4;
    my $bytes_in_a_row = $bytes_in_a_chunk * 8;
    
    # this is bit slow, but only used for debugging
    for (my $i = 0; $i < $l; $i += 1) {
        if ($i % $bytes_in_a_row == 0 && $i != 0) {
            $out .= "\n";
        } elsif ($i % $bytes_in_a_chunk == 0 && $i != 0) {
            $out .= ' ';
        }
        $out .= sprintf('%02x', ord(substr($s, $i, 1)));
    }
    
    return $out;
}

sub new 
{
    my $class = shift;
    my $self = bless { @_ }, $class;
    
    $self->{'initialized'} = 0;
    $self->{'version'} = $VERSION;
    
    # store config
    my %h = @_;
    $self->{'config'} = \%h;
    #print "settings: " . Dumper(\%h);
    
    $self->{'pkts_tx'} = 0;
    $self->{'pkts_rx'} = 0;
    $self->{'bytes_tx'} = 0;
    $self->{'bytes_rx'} = 0;
    
    $self->{'sock'} = $self->{'config'}->{'sock'};
    
    $self->{'debug'} = ( $self->{'config'}->{'debug'} );
    $self->{'log_prefix'} = $self;
    $self->{'log_prefix'} =~ s/=.*//;
    
    $self->_debug('initialized');
    
    $self->_clear_errors();
    return $self;
}



# clear error flags

sub _clear_errors($)
{
    my($self) = @_;
    
    $self->{'last_err_code'} = 'ok';
    $self->{'last_err_msg'} = 'no error reported';
}

#
#    Logg tools
#

sub log_time()
{
    my(@tf) = gmtime();
    return sprintf("%04d.%02d.%02d %02d:%02d:%02d",
        $tf[5]+1900, $tf[4]+1, $tf[3], $tf[2], $tf[1], $tf[0]);
}

sub _log($$)
{
    my($self, $msg) = @_;
    
    warn log_time() . ' ' . $self->{'log_prefix'} . " $msg\n";
}

sub _debug($$)
{
    my($self, $msg) = @_;
    
    return if (!$self->{'debug'});
    
    $self->_log("DEB: $msg");
}

sub _info($$)
{
    my($self, $msg) = @_;
    
    $self->_log("FYI: $msg");
}

sub _fail($$$)
{
    my($self, $rh, $code) = @_;
    
    $rh->{'err_code'} = $code;
    
    $self->_log("WTF: $code");
    
    return 0;
}

sub _crash($$$)
{
    my($self, $rh, $code) = @_;
    
    $rh->{'err_code'} = $code;
    
    $self->_log("OMG: $code");
    
    exit(1);
}

=over

=item set_debug($enable)

Enable or disable debug printout in module. Debug output goes to standard error.

=back

=cut

sub set_debug($$)
{
    my($self, $status) = @_;
    $self->{'debug'} = ($status);
}

=over

=item _decode_ber($data, $index)

Decode var-length int from data. Appear to be encoded
like in BER/ASN.1/SNMP:

"base-128 in big-endian order where the 8th bit is 1 if more bytes follow and 0 for the last byte"
(wikipedia)

Start decode from given position. Return list of decoded int value
and index *after* last decode byte (where decode of following
data continues).

=back

=cut

sub _decode_ber_int($$$)
{
    my($self, $data, $i) = @_;
    
    my $i_start = $i;
    my $n = unpack('C', substr($data, $i, 1));
    my $sign = $n & 0x40;
    my $no = $n & 0x3f;
    
    while ($n & 0x80) {
        $i++;
        $n = unpack('C', substr($data, $i, 1));
        $no = $no * 128 + ($n & 0x7f);
    }
    
    my $c = $i - $i_start + 1;
    #$self->_debug("_decode_ber_int of $c bytes ($i_start...$i): $no - 0x" . _hex_dump(substr($data, $i_start, $c)));
    $i++;
    
    # TODO: which way the sign is?
    
    return ($no, $i);
}

sub _decode_ber_uint($$$)
{
    my($self, $data, $i) = @_;
    
    my $i_start = $i;
    my $n = unpack('C', substr($data, $i, 1));
    my $no = $n & 0x7f;
    
    while ($n & 0x80) {
        $i++;
        $n = unpack('C', substr($data, $i, 1));
        $no = $no * 128 + ($n & 0x7f);
    }
    
    my $c = $i - $i_start + 1;
    #$self->_debug("_decode_ber_uint of $c bytes ($i_start...$i): $no - 0x" . _hex_dump(substr($data, $i_start, $c)));
    $i++;
    
    return ($no, $i);
}

sub _encode_ber_uint($$)
{
    my($self, $int) = @_;
    
    my $out = '';
    
    #$self->_debug("_encode_ber_uint $int");
    
    my $firstbit = 0;
    while ($int) {
        $out = pack('C', ($int & 0x7f) | $firstbit ) . $out;
        $int = $int >> 7;
        $firstbit = 0x80;
    }
    $out = pack('C', 0) if ($out eq '');
    
    #$self->_debug("result: " . _hex_dump($out));
    
    return $out;
}

=over

=item _make_addr($id)

With configured CAI network number and radio ID number, generate
IP address of radio. Retur packed sockaddr_in format
which can pass to sendmsg() direct.

=back

=cut

sub _make_addr($$)
{
    my($self, $id) = @_;
    
    my $host = $self->{'config'}->{'cai_net'} . '.' . (($id >> 16) & 0xff) .'.' . (($id >> 8) & 0xff) . '.' . ($id & 0xff);
    my $hisiaddr = inet_aton($host);
    #$self->_debug("_make_addr $id: $host " . $self->{'config'}->{'port'});
    my $sin = sockaddr_in($self->{'config'}->{'port'}, $hisiaddr);
    
    return $sin;
}

=over

=item send($id, $data)

Send binary message UDP to radio ID.

=back

=cut

sub _send($$$;$)
{
    my($self, $id, $data, $prefix) = @_;
    
    my $out = $self->_pack($data, $prefix);
    
    $self->_debug("_send to $id:" . $self->{'config'}->{'port'} . ": " . _hex_dump($out));
    
    $self->{'sock'}->send($out, 0, $self->_make_addr($id));
    
    $self->{'pkts_tx'} += 1;
    $self->{'bytes_tx'} += length($out);
}

sub _rx_accounting($$)
{
    my($self, $msg) = @_;
    
    $self->{'pkts_rx'} += 1;
    $self->{'bytes_rx'} += length($msg);
}

sub _pack($$;$)
{
    my($self, $data, $prefix) = @_;
    
    my $out = pack('n', length($data)) . $data;
    
    if (defined $prefix) {
        $out = $prefix . $out;
    }
    
    return $out;
}


1;

