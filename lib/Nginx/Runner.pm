package Nginx::Runner;

use strict;
use warnings;
use 5.008_001;

our $VERSION = '0.0000001';

use Nginx::Runner::Config;
use File::Temp;
use Time::HiRes 'usleep';

sub new {
    bless {
        nginx_bin  => "/usr/sbin/nginx",
        error_log  => "/tmp/nginx.error",
        access_log => "/tmp/nginx.access",
        servers    => []
      },
      shift;
}

sub proxy {
    my ($self, $src, $dst, @args) = @_;

    push @{$self->{servers}},
      [ server => [
            [listen   => $src],
            [location => '/' => [[proxy_pass => "http://$dst"], @args]]
        ]
      ];

    $self;
}

sub is_running { $_[0]->{pid} }

sub run {
    my $self = shift;

    return if $self->is_running;

    my ($pid_fh, $pid_fn) =
      File::Temp::tempfile(UNLINK => 1, SUFFIX => '.pid');

    my $config = [
        [worker_processes => 1],
        [error_log        => $self->{error_log}, "info"],
        [pid              => $pid_fn],
        [daemon           => "on"],
        [events => [[worker_connections => 1024], [use => "epoll"]]],
        [http => [[access_log => $self->{access_log}], @{$self->{servers}}]]
    ];

    my ($conf_fh, $conf_fn) =
      File::Temp::tempfile(UNLINK => 1, SUFFIX => '.conf');
    $conf_fh->print(Nginx::Runner::Config::encode($config));
    $conf_fh->close;

    my $res = system($self->{nginx_bin}, '-c' => $conf_fn);
    die "Unable to run nginx" if $res;

    my $pid;
    while (!($pid = <$pid_fh>)) { usleep 100; }
    $pid_fh->close;

    $self->{pid} = $pid;
}

sub stop {
    my $self = shift;

    kill "TERM", delete $self->{pid};
}

1;
__END__

=head1 NAME

Nginx::Runner - run nginx proxy server

=head1 SYNOPSIS

    use Nginx::Runner;

    my $nginx = Nginx::Runner->new;

    $nginx->proxy("127.0.0.1:8080" => "127.0.0.1:3000")->run;

    $SIG{INT} = sub {$nginx->stop};
    sleep;

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2012, Sergey Zasenko.

This program is free software, you can redistribute it and/or modify it under
the same terms as Perl 5.14.

=head1 SEE ALSO

    L<http://nginx.org>

=cut