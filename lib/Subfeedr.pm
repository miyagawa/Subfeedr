package Subfeedr;

use strict;
use 5.008_001;
our $VERSION = '0.01';

use Tatsumaki::Application;
use Subfeedr::Handler;
use Subfeedr::Worker;

sub app {
    my $app = Tatsumaki::Application->new([
        '/' => 'Subfeedr::Handler',
    ]);
    $app->add_service( Subfeedr::Worker->new );
    $app;
}

1;
__END__

=encoding utf-8

=for stopwords

=head1 NAME

Subfeedr - Open PubSubHubbub Hub that does polling and proxy PuSH pings

=head1 SYNOPSIS

  > redis-server &
  > subfeedr

=head1 DESCRIPTION

Subfeedr is an open PubSubHubbub hub implementation that also does
periodically polling feeds so anyone can subscribe to any feeds that
are not PubSubHubbub publishers.

Subfeedr is written in Perl and built on top of Tatsumaki, Plack,
AnyEvent and Redis data store. Polling, serving web requests and
querying database are all done in a non-blocking event loop.

=head1 NOTE

The name Subfeedr is given with my respect to Superfeedr. This
implementation should be considered naive, and not production ready
nor scalable. It must be fun to hack on though!

=head1 AUTHOR

Tatsuhiko Miyagawa E<lt>miyagawa@bulknews.netE<gt>

=head1 LICENSE

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=head1 SEE ALSO

L<http://pubsubhubbub.appspot.com/> L<http://superfeedr.com/> L<Tatsumaki> L<Plack> L<AnyEvent> L<AnyEvent::Redis>

=cut
