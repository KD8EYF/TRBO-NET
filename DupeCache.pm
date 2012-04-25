
package TRBO::DupeCache;

=head1 NAME

TRBO::DupeCache - module for caching message IDs and detecting dupes

=head1 ABSTRACT

=head1 FUNCTIONS

=cut


use TRBO::Common;
our @ISA = ('TRBO::Common');

sub init($)
{
    my($self) = @_;
    
    $self->{'debug'} = 1;
    
    $self->_debug('init');
    
    $self->{'cache'} = {};
}

sub add($$)
{
    my($self, $key) = @_;
    
    if (defined $self->{'cache'}->{$key}) {
        $self->_debug("cache hit: $key");
        return 1;
    }
    
    $self->_debug("add: $key");
    $self->{'cache'}->{$key} = time();
    
    return 0;
}

sub scan($$)
{
    my($self, $timeout) = @_;
    
    #$self->_debug("scan, timeout $timeout");
    
    my $now = time();
    my $expire_below = $now - $timeout;
    $c = $self->{'cache'};
    
    foreach my $k (keys %{ $self->{'cache'} }) {
        #$self->_debug("checking: $k");
        if ($c->{$k} > $now) {
            $c->{$k} = $now; # clock jumpd backwards
        } elsif ($c->{$k} < $expire_below) {
            delete $c->{$k};
            #$self->_debug("evicted: $k");
        }
    }
}


1;

