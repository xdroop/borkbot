package Borkbot;
use Moo;
use MooX::Options;

use Try::Tiny;
use YAML::Tiny;
use Mojo::Pg;
use Mojo::UserAgent;

use again;
use experimental 'postderef';

use Borkbot::Logger;
use Borkbot::IRC;
use Borkbot::Event;

our $VERSION = '0.01';

option 'config_file' => (
  is => 'ro',
  format => 's',
  short => 'C',
  default => "borkbot.yaml",
);

has 'config' => (
  is => 'lazy',
  default => sub {
    my $self = shift;
    YAML::Tiny->read($self->config_file)->[0];
  },
);

has 'pg' => (
  is => 'lazy',
  default => sub {
    my $self = shift;
    Mojo::Pg->new($self->config->{db}->%*);
  },
);

has 'ua' => (
  is => 'lazy',
  default => sub {
    Mojo::UserAgent->new;
  },
);

has 'irc' => (
  is => 'lazy',
  default => sub {
    my $self = shift;
    my $config = $self->config->{irc};

    Borkbot::IRC->new(
      server => $config->{server},
      nick => $config->{nick},
      name => $config->{ircname},
      user => $config->{username},
      tls => $config->{tls},
    );
  },
);

has 'modules' => (
  is => 'rw',
  default => sub { +{} },
);

has 'module_order' => (
  is => 'rw',
  default => sub { +[] },
);

has 'debug_events' => (
  is => 'rw',
  default => 0,
);

sub load_module {
  my ($self, $name) = @_;
  my $module = "Borkbot::Module::$name";

  log_info { "Loading $name" };
  try {
    delete $Moo::MAKERS{$module};
    require_again $module;
    $self->modules->{$name} = $module->new(
      bot => $self,
    );
    1;
  } catch {
    log_warning { "Loading $module failed: $_" };
    0;
  };
}

sub get_handlers {
  my ($self, $method) = @_;
  return grep { $_->can($method) } $self, map { $self->modules->{$_} } $self->module_order->@*;
}

sub dispatch_event {
  my ($self, $event) = @_;

  my $type = $event->type;
  my $method = "on_$type";
  my @handlers = $self->get_handlers($method);

  for my $handler (@handlers) {
    my $stop = $handler->$method($event);
    last if $stop;
  }
}

sub run {
  my ($self) = shift;
  Borkbot::Logger::set_logfile($self->config->{log}{file});
  Borkbot::Logger::set_stderr($self->config->{log}{stderr});
  log_info { "started up!" };

  for my $module ($self->config->{modules}->@*) {
    if ($self->load_module($module)) {
      push $self->module_order->@*, $module;
    }
  }
  
  $self->irc->on(irc_any => sub {
    my ($irc, $ev) = @_;
    my $event = Borkbot::Event->from_mojo_event($ev);
    log_debug { use Data::Dumper::Concise; Dumper($event) };
    $self->dispatch_event($event);
  });

  $self->irc->connect(sub {
      my ($irc, $err) = @_;
      if ($err) {
        $self->dispatch_event(Borkbot::Event->new(type => 'irc_connect_error', error => $err));
      } else {
        $self->dispatch_event(Borkbot::Event->new(type => 'irc_connected'));
      }
  });
  Mojo::IOLoop->start;
}

1;
