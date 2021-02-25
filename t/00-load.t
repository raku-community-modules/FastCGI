use lib 'lib';

use Test;

plan 8;

use-ok 'FastCGI';
use-ok 'FastCGI::Connection';
use-ok "FastCGI::Constants";
use-ok "FastCGI::Errors";
use-ok "FastCGI::Logger";
use-ok "FastCGI::Request";
use-ok "FastCGI::Protocol";
use-ok "FastCGI::Protocol::Constants";
