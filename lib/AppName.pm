package AppName;
use Dancer ':syntax';

use utf8;
use strict;
use warnings;

use Dancer::Plugin::DBIC;

our $VERSION = '0.1';

get '/' => sub {
  template 'index';
};

1;
