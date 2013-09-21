
package TRBO::NET;

=head1 NAME

TRBO::NET - turbo network communicator.

=head1 FUNCTIONS

=cut

use strict;
use warnings;

use Data::Dumper;
use IO::Socket::INET;
use IO::Select;

use TRBO::Common;
use TRBO::ARS;
use TRBO::LOC;
use TRBO::TMS;
our @ISA = ('TRBO::Common');

our $VERSION = '1.00';

=head1 OBJECT INTERFACE

=over

=item new(config)

Returns new instance of TRBO::NET communicator.

  my $net = new TRBO::NET(
    'port' => 4005,
    'debug' => 0,
  );

=back 

=cut

sub new 
{
    my $class = shift;
    my $self = bless { @_ }, $class;
    
    $self->{'initialized'} = 0;
    $self->{'version'} = $VERSION;
    
    $self->{'ars_clients'} = 0;
    $self->{'ars_clients_here'} = 0;
    
    # store config
    my %h = @_;
    $self->{'config'} = \%h;
    #print "settings: " . Dumper(\%h);
    
    my %defaults = (
        'registry_poll_interval' => 900,
        'registry_timeout' => 1800,
        'tms_init_retry_interval' => 10,
        'tms_max_retry_interval' => 20*60,
        'tms_queue_max_age' => 2*3600,
        'debug' => 0,
    );
    
    foreach my $k (keys %defaults) {
        if (!defined $self->{'config'}->{$k}) {
            $self->{'config'}->{$k} = $defaults{$k}
        }
    }
    
    $self->{'debug'} = ( $self->{'config'}->{'debug'} );
    $self->{'log_prefix'} = $self;
    $self->{'log_prefix'} =~ s/=.*//;
    
    $self->_debug('initializing, config: ' . Dumper($self->{'config'}));
    
    $self->_clear_errors();
    
    $self->{'timeout'} = 10;
    if (defined $h{'timeout'}) {
        if ($h{'timeout'} < 2) {
            return $self->_critical("Too short timeout");
        }
        if ($h{'timeout'} > 300) {
            return $self->_critical("Too long timeout");
        }
        $self->{'timeout'} = $h{'timeout'}
    }
    
    $self->{'sel'} = IO::Select->new();
    
    foreach my $type ('ars', 'tms', 'loc') {
        my $port = $h{$type . '_port'};
        
        my $s = IO::Socket::INET->new(
            LocalPort => $port,
            Proto => 'udp'
        );
        
        if (!$s) {
            warn "TRBO::NET failed to create $type UDP socket: $!\n";
            return 0;
        }
        
        $self->{$type . '_sock'} = $s;
        $self->{'sel'}->add($s);
        $self->_debug("listening on $type port $port");
    }
    
    $self->{'ars'} = TRBO::ARS->new(
        'debug' => ($h{'debug'}),
        'sock' => $self->{'ars_sock'},
        'cai_net' => $h{'cai_net'},
        'port' => $h{'ars_port'},
    );
    $self->{'loc'} = TRBO::LOC->new(
        'debug' => ($h{'debug'}),
        'sock' => $self->{'loc_sock'},
        'cai_net' => $h{'cai_net'},
        'port' => $h{'loc_port'},
    );
    $self->{'tms'} = TRBO::TMS->new(
        'debug' => ($h{'debug'}),
        'sock' => $self->{'tms_sock'},
        'cai_net' => $h{'cai_net'},
        'port' => $h{'tms_port'},
        'tms_init_retry_interval' => $h{'tms_init_retry_interval'},
        'tms_max_retry_interval' => $h{'tms_max_retry_interval'},
        'tms_queue_max_age' => $h{'tms_queue_max_age'},
    );
    $self->{'tms'}->init();
    
    # registry of radios currently followed
    $self->{'registry'} = {};
    $self->{'reg_call'} = {};
    
    $self->{'pkts_rx'} = 0;
    $self->{'bytes_rx'} = 0;
    
    return $self;
}

=over

=item add_radio($id)

Add radio to radio registry. Returns reference
to registry item.

=back

=cut

sub add_radio($$)
{
    my($self, $id) = @_;
    
    my %h = (
        'id' => $id,
        'first_heard' => 0,
        'last_heard' => 0,
        'last_poll_tx' => 0,
        'last_poll_rx' => 0,
        'state' => 'away',
    );
    
    $self->{'registry'}->{$id} = \%h;
    
    $self->{'ars_clients'} += 1;
    
    return $self->{'registry'}->{$id};
}

=over

=item configure_radio($id, $hashref)

Configure radio with callsign, and add to registry.

=back

=cut

sub configure_radio($$)
{
    my($self, $rx) = @_;
    
    $self->_debug("configuring radio " . $rx->{'id'} . ": " . $rx->{'callsign'});
    
    my $radio = $self->add_radio($rx->{'id'});
    
    $radio->{'callsign'} = $rx->{'callsign'};
    $self->{'reg_call'}->{$rx->{'callsign'}} = $radio;
    
    return $radio;
}

=over

=item register_radio($id, $hashref)

Mark that th radio indicated by received packet is
currently registered on network.

=back

=cut

sub register_radio($$)
{
    my($self, $rx) = @_;
    
    $self->_debug("registering radio " . $rx->{'src_id'});
    $self->_info($rx->{'src_id'} . ": Registering on net");
    
    my $radio;
    if (!defined $self->{'registry'}->{$rx->{'src_id'}}) {
        $radio = $self->add_radio($rx->{'src_id'});
    } else {
        $radio = $self->{'registry'}->{$rx->{'src_id'}};
    }
    
    $radio->{'first_heard'}
        = $radio->{'last_heard'}
        = $radio->{'last_poll_tx'}
        = $radio->{'last_poll_rx'}
        = time();
    
    $self->_registry_here($rx->{'src_id'});
}

=over

=item registry_find_call($id, $callsign)

Find radio from registry by callsign.

=back

=cut

sub registry_find_call($$)
{
    my($self, $call) = @_;
    
    return if (!defined $self->{'reg_call'}->{$call});
    
    return $self->{'reg_call'}->{$call};
}

sub _registry_heard($$)
{
    my($self, $id) = @_;
    
    if (defined $self->{'registry'}->{$id}) {
        $self->_debug("registry updating last_heard: $id");
        $self->{'registry'}->{$id}->{'last_heard'} = time();
        if ($self->{'registry'}->{$id}->{'first_heard'} < 1) {
            $self->{'registry'}->{$id}->{'first_heard'} = time();
        }
        return;
    }
    
    # we received packet from radio we don't know about.
    # How to tell radio to give us new Hello!
}

sub _registry_pong($$)
{
    my($self, $id) = @_;
    
    if (defined $self->{'registry'}->{$id}) {
        $self->_debug("registry updating last_poll_rx: $id");
        $self->{'registry'}->{$id}->{'last_poll_rx'} = time();
        $self->_registry_here($id);
    }
}

sub _registry_here($$)
{
    my($self, $id) = @_;
    if (!defined $self->{'registry'}->{$id}) {
        return;
    }
    
    if ($self->{'registry'}->{$id}->{'state'} ne 'here') {
        $self->{'ars_clients_here'} += 1;
        $self->_info($id . ": Marking here");
    }
    $self->{'registry'}->{$id}->{'state'} = 'here';
}

sub _registry_last($$$)
{
    my($self, $id, $reason) = @_;
    if (!defined $self->{'registry'}->{$id}) {
        return;
    }
    
    $self->{'registry'}->{$id}->{'heard_what'} = $reason;
}

sub _registry_leave($$$)
{
    my($self, $id, $reason) = @_;
    if (!defined $self->{'registry'}->{$id}) {
        return;
    }
    
    if ($self->{'registry'}->{$id}->{'state'} eq 'here') {
        $self->{'ars_clients_here'} -= 1;
    }
    
    $self->{'registry'}->{$id}->{'state'} = 'away';
    $self->{'registry'}->{$id}->{'away_reason'} = $reason;
    $self->_info($id . ": Marking away ($reason)");
}

sub _registry_get($$)
{
    my($self, $id) = @_;
    if (!defined $self->{'registry'}->{$id}) {
        return;
    }
    
    return $self->{'registry'}->{$id};
}

=over

=item registry_scan()

Scan through radio registry and poll / timeout
radios as necessary.

=back

=cut

sub registry_scan($;$)
{
    my($self, $noping) = @_;
    
    my $now = time();
    $self->{'ars_clients_here'} = 0;
    
    foreach my $id (keys %{ $self->{'registry'} }) {
        my $r = $self->{'registry'}->{$id};
        #print Dumper($r);
        if ($r->{'state'} ne 'here') {
            # no polling for stations which are not here
            next;
        }
        $self->{'ars_clients_here'} += 1;
        if ($now - $r->{'last_poll_rx'} > $self->{'config'}->{'registry_timeout'}
            && $now - $r->{'last_heard'} > $self->{'config'}->{'registry_timeout'}) {
            #$self->_debug("registry marking away after timeout: " . $r->{'id'});
            $self->_registry_leave($r->{'id'}, 'timeout');
            next;
        }
        if (!$noping && ($now - $r->{'last_heard'} > $self->{'config'}->{'registry_poll_interval'}) && ($now - $r->{'last_poll_tx'} > $self->{'config'}->{'registry_poll_interval'})) {
            $r->{'last_poll_tx'} = $now;
            $self->{'ars'}->ping($r->{'id'});
        }
    }
}

=over

=item receive()

Receive UDP packets on sockets and pass them to other modules.

=back

=cut


sub receive($)
{
    my($self) = @_;
    
    # wait for UDP packets on any of sockets
    my @ready = $self->{'sel'}->can_read(1);
    
    if (!@ready) {
        #$self->_debug("select timed out");
        return;
    }
    
    # only read from first one, for now
    my $fh = shift @ready;
    
    my $msg;
    my $remote_address = recv($fh, $msg, 1500, 0);
    
    $self->{'pkts_rx'} +=  1;
    $self->{'bytes_rx'} += length($msg);
    
    if (!defined $remote_address) {
        $self->_debug("recv on socket failed");
        return;
    }
    
    my ($peer_port, $peer_addr) = unpack_sockaddr_in($remote_address);
    my $addr_s = inet_ntoa($peer_addr);
    
    $self->_debug("received from $addr_s: $peer_port: " . length($msg) . " bytes:");
    $self->_debug(TRBO::Common::_hex_dump($msg));
    
    # decode any information available in IP header
    my %h = (
        'src_ip' => $addr_s,
        'src_port' => $peer_port,
        'msg' => 'unknown',
    );
    
    my @t = split(/\./, $addr_s);
    $h{'src_cai'} = $t[0] * 1;
    $h{'src_id'} = $t[3] + $t[2]*256 + $t[1]*256*256;
    
    if ($h{'src_cai'} != $self->{'config'}->{'cai_net'}) {
        $self->_fail(\%h, 'invalid_cai');
        return \%h;
    }
    
    $self->_registry_heard($h{'src_id'});
    
    $h{'registry'} = $self->_registry_get($h{'src_id'});
    
    # multiplex to protocol handlers
    if ($peer_port eq $self->{'config'}->{'ars_port'}) {
        my $ret = $self->{'ars'}->decode(\%h, $msg);
        
        if ($h{'msg'} eq 'hello') {
            $self->{'ars'}->ack_hello($h{'src_id'});
            $self->_registry_last($h{'src_id'}, 'hello'); # mark it as being present, too
        } elsif ($h{'msg'} eq 'pong') {
            $self->_registry_pong($h{'src_id'});
            $self->_registry_last($h{'src_id'}, 'pong'); # mark it as being present, too
        } elsif ($h{'msg'} eq 'leave') {
            $self->_registry_leave($h{'src_id'}, 'leave');
        }
        
    } elsif ($peer_port eq $self->{'config'}->{'loc_port'}) {
        $self->_registry_here($h{'src_id'}); # mark it as being present, too
        $self->{'loc'}->decode(\%h, $msg);
        $self->_registry_last($h{'src_id'}, (defined $h{'latitude'}) ? 'loc' : 'loc, no fix');
    } elsif ($peer_port eq $self->{'config'}->{'tms_port'}) {
        $self->{'tms'}->tms_decode(\%h, $msg);
        $self->_registry_last($h{'src_id'}, 'tms'); # mark it as being present, too
        if ($h{'msg'} eq 'msg') {
            $self->{'tms'}->ack_msg(\%h);
            $self->_registry_last($h{'src_id'}, 'tms msg in'); # mark it as being present, too
        }
    }
    
    return \%h;
}

1;

