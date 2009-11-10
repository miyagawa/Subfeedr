package Subfeedr::Worker;
use Moose;
extends 'Tatsumaki::Service';

use Subfeedr::DataStore;
use Tatsumaki::HTTPClient;
use Tatsumaki::MessageQueue;
use Time::HiRes;
use Try::Tiny;
use AnyEvent;
use JSON;
use XML::Feed;
use Digest::SHA;

our $FeedInterval = $ENV{SUBFEEDR_INTERVAL} || 60 * 15;

sub start {
    my $self = shift;

    my $t; $t = AE::timer 0, 15, sub {
        scalar $t;
        my $ds = Subfeedr::DataStore->new('known_feed');
        $ds->sort('set', by => 'next_fetch.*', get => 'feed.*', limit => "0 20", sub {
            my $feeds = shift;
            for my $feed (map JSON::decode_json($_), @$feeds) {
                next if $feed->{next_fetch} && $feed->{next_fetch} > time;
                $self->work_url($feed->{url});
            }
        });
    };

    my $mq = Tatsumaki::MessageQueue->instance('feed_fetch');
    $mq->poll("worker", sub {
        my $url = shift;
        $self->work_url($url);
    });
}

sub work_url {
    my($self, $url) = @_;
    warn "Polling $url\n";

    Tatsumaki::HTTPClient->new->get($url, sub {
        my $res = shift;
        my $sha1 = Digest::SHA::sha1_hex($url);

        try {
            my $feed = XML::Feed->parse(\$res->content) or die "Parsing feed ($url) failed";

            my @new;
            my $cv = AE::cv;
            $cv->begin(sub { $self->notify($sha1, $url, $feed, \@new) if @new });

            for my $entry ($feed->entries) {
                next unless $entry->id;
                $cv->begin;

                my $sha_id   = $sha1 . "." . Digest::SHA::sha1_hex($entry->id);
                my $sha_body = Digest::SHA::sha1_hex($entry->content->body);
                Subfeedr::DataStore->new('entry')->get($sha_id, sub {
                    my $v = shift;
                    if (!$v or $v ne $sha_body) {
                        push @new, $entry;
                        Subfeedr::DataStore->new('entry')->set($sha_id, $sha_body);
                    }
                    $cv->end;
                });
            }
            $cv->end;
        } catch {
            warn "Fetcher ERROR: $_";
        };

        # TODO smart polling
        my $time = Time::HiRes::gettimeofday + $FeedInterval;
        $time += 60 * 60 if $res->is_error;
        warn "Scheduling next poll for $url on $time\n";

        Subfeedr::DataStore->new('next_fetch')->set($sha1, $time);
        Subfeedr::DataStore->new('feed')->set($sha1, JSON::encode_json({
            sha1 => $sha1,
            url  => $url,
            next_fetch => $time,
        }));
    });
}

sub notify {
    my($self, $sha1, $url, $feed, $entries) = @_;

    my $how_many = @$entries;
    warn "Found $how_many entries for $url\n";

    my $payload = $self->post_payload($feed, $entries);
    my $mime_type = $feed->format =~ /RSS/ ? 'application/rss+xml' : 'application/atom+xml';

    Subfeedr::DataStore->new('subscription')->sort($sha1, get => 'subscriber.*', sub {
        my $subs = shift;
        for my $subscriber (map JSON::decode_json($_), @$subs) {
            warn "POSTing updates for $url to $subscriber->{callback}\n";
            my $hmac = Digest::SHA::hmac_sha1($payload, $subscriber->{secret});
            my $req = HTTP::Request->new(POST => $subscriber->{callback});
            $req->content_type($mime_type);
            $req->header('X-Hub-Signature' => "sha1=$hmac");
            $req->content_length(length $payload);
            $req->content($payload);

            Tatsumaki::HTTPClient->new->request($req, sub {
                my $res = shift;
                if ($res->is_error) {
                    # TODO retry
                }
            });
        }
    });
}

sub post_payload {
    my($self, $feed, $entries) = @_;

    local $XML::Atom::ForceUnicode = 1;

    # TODO create XML::Feed::Diff or something to do this
    my $format = (split / /, $feed->format)[0];

    my $new = XML::Feed->new($format);
    for my $field (qw( title link description language author copyright modified generator )) {
        my $val = $feed->$field();
        next unless defined $val;
        $new->$field($val);
    }

    for my $entry (@$entries) {
        $new->add_entry($entry->convert($format));
    }

    my $payload = $new->as_xml;
    utf8::encode($payload) if utf8::is_utf8($payload); # Ugh

    return $payload;
}

1;
