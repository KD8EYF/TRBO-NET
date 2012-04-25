
package TRBO::ARS;

=head1 NAME

TRBO::ARS - ARS parser.

=head1 ABSTRACT

=head1 DESCRIPTION

=head1 FUNCTIONS

=cut

# Packets obtained using wireshark:
#
# query radio: "are you there?"
# 00 01 74
# answer "yes i'm here"
# 00 01 3f

# radio says "i'm going away."
# 00 01 31



use strict;
use warnings;

use Data::Dumper;

use TRBO::Common;
our @ISA = ('TRBO::Common');

=over

=item decode($data)

Decode Automatic Registration Service packet

=back

=cut

sub decode($$$)
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
    
    $rh->{'class'} = 'ars';
    
    my($op, $n) = $self->_decode_ber_uint($data, 2);
    
    $self->_debug("ars op " . sprintf('%04x', $op));
    
    if ($op == 0x3820) {
        # first HELLO after powerup is always 0x3820
        return $self->_decode_hello($rh, substr($data, 4));
    } elsif ($op == 0x3840) {
        # following HELLOs, maybe 30 mins from initial, are
        # 0x3840. Go figure.
        return $self->_decode_hello($rh, substr($data, 4));
    } elsif ($op == 0x3f) {
        $self->_debug("ARS pong from " . $rh->{'src_id'});
        $rh->{'msg'} = 'pong';
        return 1;
    } elsif ($op == 0x31) {
        $self->_info($rh->{'src_id'} . ": LEAVE NET");
        $rh->{'msg'} = 'leave';
        return 1;
    }
    
    return $self->_fail($rh, 'unknown');
}

sub _decode_hello($$$)
{
    my($self, $rh, $data) = @_;
    
    my $addr_len = unpack('C', substr($data, 0, 1));
    
    #warn "addr_len $addr_len\n";
    
    my $addr = substr($data, 1, $addr_len);
    
    $rh->{'msg'} = 'hello';
    $rh->{'id'} = $addr;
    
    #warn "addr: '$addr'\n";
    
    $self->_info("$addr: HELLO received ($addr)");
    
    # should be answered with 00 02 BF 01
    
    return 1;
}

=over

=item ack_hello($id)

Sends ACK to HELLO packet

=back

=cut

sub ack_hello($$)
{
    my($self, $id) = @_;
    
    $self->_debug("sending hello ack to $id");
    $self->_send($id, pack('n', 0xBF01));
}

=over

=item ping($id)

Ping radio

=back

=cut

sub ping($$)
{
    my($self, $id) = @_;
    
    $self->_debug("sending ping to $id");
    $self->_send($id, pack('C', 0x74));
}

1;

