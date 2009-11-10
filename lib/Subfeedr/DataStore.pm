package Subfeedr::DataStore;
use Moose;
use AnyEvent::Redis;

# Schema:
#   known_feed.set:    Set of SHA1 for the known feeds
#   next_fetch.{id}:   Next fetched time of feeds ({id} = SHA1 of URL)
#   feed.{id}:         JSON object for the feed
#   entry.{id}.{eid}:  SHA1 of entry body ({eid} = SHA1 of entry ID)
#   subscription.set:  Set of SHA1 for the subscribers
#   subscriber.{sid}:  JSON object for the subscriber ({sid} = SHA1 of callback URL)

has prefix => (is => 'rw', isa => 'Str');

around BUILDARGS => sub {
    my $orig = shift;
    my $class = shift;
    $class->$orig(prefix => shift);
};

our $redis;

sub redis {
    $redis ||= AnyEvent::Redis->new;
}

our $AUTOLOAD;

sub AUTOLOAD {
    my $self = shift;
    my($key, @args) = @_;

    (my $method = $AUTOLOAD) =~ s/.*:://;

    if (defined $key) {
        my $k = sprintf '%s.%s', $self->prefix, $key;
        return $self->redis->$method($k, @args);
    } else {
        return $self->redis->$method(@_);
    }
}

1;
