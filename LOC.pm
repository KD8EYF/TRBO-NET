
package TRBO::LOC;

=head1 NAME

TRBO::LOC - trbo location packet parser.

=head1 DESCRIPTION

=head1 FUNCTIONS

=cut

use strict;
use warnings;

use Data::Dumper;

use TRBO::Common;
our @ISA = ('TRBO::Common');

=over

=item decode($data)

Decodes packet on location port

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
    
    $rh->{'class'} = 'loc';
    
    my $cmd = unpack('C', substr($data, 0, 1));
    my $dlen = unpack('C', substr($data, 1, 1));
    $self->_debug(sprintf("LOC cmd %02x dlen $dlen plen $plen", $cmd));
    
    if ($dlen != $plen - 2) {
        return $self->_fail($rh, 'plen_mismatch');
    }
    
    
    if ($cmd == 0x0d) {
        my $token = unpack('C', substr($data, 8, 1));
        $self->_debug(sprintf("0x0d: location report, token %02x", $token));
        if ($token != 0x69 && $token != 0x51) {
            $self->_info(sprintf("%s: LOC RX (timed) token 0x%02x indicates no GPS fix", $rh->{'src_id'}, $token));
            return 1;
        }
        return $self->_decode_loc($rh, $data, $plen);
    } elsif ($cmd == 0x07) {
        my $token = unpack('C', substr($data, 8, 1));
        $self->_debug(sprintf("0x07: immediate location answer, token %02x", $token));
        if ($token != 0x69 && $token != 0x51) {
            $self->_info(sprintf("%s: LOC RX (immediate) token 0x%02x indicates no GPS fix", $rh->{'src_id'}, $token));
            return 1;
        }
        return $self->_decode_loc($rh, $data, $plen);
    } elsif ($cmd == 0x0b) {
        $self->_debug("0x0b: command reply: " . TRBO::Common::_hex_dump(substr($data, 2)));
        if ($dlen == 8) {
            my $op = unpack('n', substr($data, 8, 2));
            $self->_debug(sprintf("0x0b op %04x", $op));
            if ($op == 0x3716) {
                $self->_debug("0x0b: command reply: 0x3716, probably OK");
            }
            $rh->{'msg'} = 'ack';
            return 1;
        } elsif ($dlen == 7) {
            my $op = unpack('C', substr($data, 8, 1));
            $self->_debug(sprintf("0x0b op %02x", $op));
            if ($op == 0x38) {
                $self->_debug("0x0b: command reply: 0x38, probably OK");
            }
            $rh->{'msg'} = 'ack';
            return 1;
        }
    } elsif ($cmd == 0x11) {
        $self->_debug("0x11: command reply: " . TRBO::Common::_hex_dump(substr($data, 2)));
        $rh->{'msg'} = 'ack';
        return 1;
    }
    
    return $self->_fail($rh, 'unknown');
}

sub _decode_loc($$$$)
{
    my($self, $rh, $data, $plen) = @_;
    
    # Latitude and longitude are packed as network byte order integers with
    # little scaling to make them firmly integers in packet.
    # This was pain to get right. GPS simulator helped.
    # First bit in integer is sign.    
    my $x = 45.0 / 1073741824.0;
 
# Old Code working
    my $lat = unpack('N', substr($data, 9, 4)) * $x;
    my $lng = -(360-unpack('N', substr($data, 13, 4)) * 2 * $x);

# New code Islas Cainman
#    my $lat_i = unpack('N', substr($data, 9, 4));
#    my $lat = ($lat_i & 0x7FFFFFFF) * $x;
#    $lat *= -1 if ($lat_i & 0x80000000);
   
#    my $lng_i = unpack('N', substr($data, 13, 4));
#    my $lng = ($lng_i & 0x7FFFFFFF) * 2 * $x;
#    $lng *= -1 if ($lng_i & 0x80000000);

    
    # Altitude and speed probably encoded bit like in BER/ASN.1/SNMP:
    # "base-128 in big-endian order where the 8th bit is 1 if more bytes follow and 0 for the last byte"
    # (the same encoding is used in ARS config packets too)
    my $i = 17; # this is where altitude and speed probably are.
    my($alt, $speed) = (0, 0);
    
    $self->_info(sprintf('%s: LOC RX lat %.6f lng %.6f speed %d alt %d', $rh->{'src_id'}, $lat, $lng, $speed, $alt));
    
    $rh->{'msg'} = 'loc';
    $rh->{'latitude'} = $lat;
    $rh->{'longitude'} = $lng;
    
    #warn "addr: '$addr'\n";
    
    return 1;
}

=over

=item request_locs($id, $interval)

Send request to radio to send location packets
at specified interval.

=back

=cut

sub request_locs($$$)
{
    my($self, $id, $interval) = @_;
    
    $self->_info($id . ": Requesting location every $interval s");
    
    # disable loc sends / cancel old requests
    # apparently radio not take in new command otherwise!
    $self->request_no_locs($id);
        
    sleep(1);
    
    # have no idea what this really contains, except for interval which
    # is BER encoded in end.
    
    $self->_send($id,
        pack('n*', 0x2204, 0x3727, 0x1707)
        . pack('n*', 0x5074, 0x6934)
        . pack('C', 0x31)
        . $self->_encode_ber_uint($interval)
        , pack('C', 0x09)); # command 0x9
}

=over

=item request_no_locs($id)

Send request to radio not to send location packets.

=back

=cut

sub request_no_locs($$$)
{
    my($self, $id, $interval) = @_;
    
    # disable loc sends?
    $self->_send($id,
        pack('n*', 0x2204, 0x3727, 0x1707)
        , pack('C', 0x0f)); # command 0xf
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

