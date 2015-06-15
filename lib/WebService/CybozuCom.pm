package WebService::CybozuCom;

=encoding utf8

=head1 NAME

  WebService::CybozuCom - cybozu.com client for perl.

=head1 SYNOPSIS

  use WebService::CybozuCom
  use YAML;
  my $c = WebService::CybozuCom->new(
    domain   => 'your group name',
    username => 'your username',
    password => 'your password',
  );

  $c->login();
  my $bulletin = $c->show_bulletin();
  for my $row (@$bulletin){
    warn YAML::Dump $row;
  }

=head1 DESCRIPTION

  WebService::CybozuCom is scraping library client for perl at cybozu.com

=cut

use strict;
use warnings;
use utf8;
use Carp;
use Encode;
use JSON qw/encode_json decode_json/;
use Web::Scraper;
use WWW::Mechanize;

our $VERSION = '1.00';

=head1 CONSTRUCTOR AND STARTUP

=head2 new

Creates and returns a new cybozu.com object.

=cut

sub new {
    my $class = shift;
    my %args = @_;

    my $self = bless { %args }, $class;

    $self->{last_req} ||= time;
    $self->{interval} ||= 1;

    $self->mech();
    return $self;
}

=head1 Accessor

=over

=item B<mech>

  WWW::Mechanize object.

=cut

sub mech {
    my $self = shift;
    unless($self->{mech}){
        my $mech = WWW::Mechanize->new(
            agent      => 'Mozilla/5.0',
            cookie_jar => {},
        );
        $mech->stack_depth(10);
        $self->{mech} = $mech;
    }
    return $self->{mech};
}

=item B<interval>

sleeping time per one action by mech.

=item B<last_request_time>

request time at last;

=item B<last_content>

cache at last decoded content.

=cut

sub interval          { return shift->{interval} ||= 1    }
sub last_request_time { return shift->{last_req} ||= time }

sub last_content {
    my $self = shift;
    my $arg  = shift || '';

    if($arg){
        $self->{last_content} = $arg
    }
    return $self->{last_content} || '';
}

=item B<base_url>

=cut

sub base_url {
    my $self = shift;
    my $arg  = shift || '';

    if($arg){
        $self->{base_url} = $arg;
        $self->{conf}     = undef;
    }
    return $self->{base_url} || sprintf('https://%s.cybozu.com', $self->{domain});
}

=back

=head1 METHODS

=head2 set_last_request_time

set request time

=cut

sub set_last_request_time { shift->{last_req} = time }


=head2 post

mech post with interval.

=cut

sub post {
    my $self = shift;
    $self->_sleep_interval;
    my $res = $self->mech->post(@_);
    return $self->_content($res);
}

=head2 post_json

mech post json content with interval.

=cut
sub post_json {
    my $self  = shift;
    my $url   = shift;
    my $param = shift;
    $self->_sleep_interval;
    my $res = $self->mech->post($url,
        'Content-Type' => 'application/json',
        'Content'      => encode_json($param),
    );
    return $self->_content($res);
}

=head2 get

mech get with interval.

=cut

sub get {
    my $self = shift;
    $self->_sleep_interval;
    my $res = $self->mech->get(@_);
    return $self->_content($res);
}

=head2 conf

  url path config

=cut

sub conf {
    my $self = shift;
    unless ($self->{conf}){
        my $base_url =  $self->base_url();
        my $conf = {
            pre_login => sprintf("%s/login",                            $base_url),
            get_token => sprintf("%s/api/auth/getToken.json?_lc=ja_JP", $base_url),
            enter     => sprintf("%s/api/auth/login.json?_lc=ja_JP",    $base_url),
            bulletin  => sprintf("%s/o/ag.cgi?page=BulletinIndex",      $base_url),
        };
        $self->{conf} = $conf;
    }
    return $self->{conf};
}

=head2 request_token

get and set request_token

=cut

sub request_token {
    my $self = shift;
    unless($self->{request_token}){
        $self->get($self->conf->{pre_login},);
        my $content = $self->last_content;
        if($content =~ m{cybozu.data.REQUEST_TOKEN\s=\s'(.*)?';}){
            $self->{request_token} = $1;
        }
        else {
            warn $content;
            die 'cant get request_token';
        }
    }
    return $self->{request_token};
}

=head2 login

  sign in at cybozu.com

=cut

sub login {
    my $self = shift;

    {
        my $token = $self->request_token();
        $self->post_json( $self->conf->{get_token}, {'__REQUEST_TOKEN__' => $token });

        my $params = {
            username            => $self->{username},
            password            => $self->{password},
            keepUsername        => undef,
            redirect            => '',
            '__REQUEST_TOKEN__' => $token,
        };

        $self->post_json($self->conf->{enter}, $params);
    }
}

=head2 show_bulletin

list bulletin.

=cut

sub show_bulletin {
    my $self = shift;
    $self->get($self->conf->{bulletin});
    my $bulletin = $self->_parse_bulletin();
    return $bulletin;
}


=head1 PRIVATE METHODS.

=over

=item B<_parse_bulletin>

parse url, title, category and user name from bulletin.

=cut

sub _parse_bulletin {
    my $self = shift;
    my $html = $self->last_content;
    my $scraper = scraper {
        process '//table[@class="dataList"]', 'data' => scraper {
            process '//tr',                        'lows[]' => scraper {
                process '//td[1]/a',                        url        => '@href',
                                                            title      => 'TEXT';
                process '//td[2]',                          category   => 'TEXT';
                process '//td[3]',                          username   => 'TEXT';
                process '//td[4]',                          updated_at => 'TEXT';
            };
        };
        result 'data';
    };
    my $result = $scraper->scrape($html);
    my $bulletins = [];
    for my $colums (@ { $result->{lows}} ){
        next unless $colums->{title};
        my $bid;
        if($colums->{url} =~ m{&bid=(\d+)?&}){
            $bid = $1;
        }
        my $row = {
            url        => join('/', $self->base_url() , 'o', $colums->{url}),
            bid        => $bid,
            title      => $colums->{title},
            category   => $colums->{category},
            username   => $colums->{username},
            updated_at => $colums->{updated_at},
        };
        push @$bulletins, $row;
    }
    return $bulletins;
}

=item B<_sleep_interval>

interval for http accessing.

=cut

sub _sleep_interval {
    my $self = shift;
    my $wait = $self->interval - (time - $self->last_request_time);
    sleep $wait if $wait > 0;
    $self->set_last_request_time();
}

=item b<_content>

decode content with mech.

=cut

sub _content {
  my $self = shift;
  my $res  = shift;
  my $content = $res->decoded_content();
  $self->last_content($content);
  return $content;
}

=back

=cut

=head1 AUTHOR

likkradyus E<lt>perl {at} li.que.jpE<gt>

=head1 SEE ALSO

L<http://cybozu.com>

=head1 LICENSE

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

1;
