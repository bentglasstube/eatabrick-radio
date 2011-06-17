package Dancer::Logger::Store;

use strict;
use warnings;

use base 'Dancer::Logger::Abstract';
our $sink = [];

sub _log {
  my ($self, $level, $message) = @_;
  push @{$sink}, $self->format_message($level => $message);
}

sub fetch {
  return $sink;
}

sub clear {
  $sink = [];
}

1;

