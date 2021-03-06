package Borkbot::IRC;
use strict;
use warnings;
use Borkbot::Logger;
use Mojo::Base 'Mojo::IRC::UA';
use Parse::IRC;

has 'bot';

sub new {
  my $class = shift;
  my $self = $class->SUPER::new(
    parser => Parse::IRC->new(ctcp => 1),
    @_,
  );
  return $self;
}

sub register_default_event_handlers {
  my ($self) = @_;

  for my $event (qw(irc_ping irc_nick irc_rpl_welcome irc_rpl_isupport)) {
    $self->on($event => $self->can($event));
  }
}

sub join {
  my ($self, $channel) = @_;

  log_info { "Joining $channel" };

  $self->write('JOIN', $channel);
}

sub part {
  my ($self, $channel) = @_;

  log_info { "Leaving $channel" };

  $self->write('PART', $channel);
}

sub privmsg {
  my ($self, $target, $msg) = @_;
  $self->write('PRIVMSG', $target, ":$msg");
}

sub notice {
  my ($self, $target, $msg) = @_;
  $self->write('NOTICE', $target, ":$msg");
}

sub ctcp {
  my ($self, $target, $cmd, @args) = @_;
  $self->write('PRIVMSG', $target, $self->SUPER::ctcp($cmd, @args));
}

sub nctcp {
  my ($self, $target, $cmd, @args) = @_;
  $self->write('NOTICE', $target, $self->SUPER::ctcp($cmd, @args));
}

sub action {
  my ($self, $target, $action) = @_;
  $self->ctcp($target, ACTION => $action);
}

1;
