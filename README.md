[![Actions Status](https://github.com/raku-community-modules/FastCGI/actions/workflows/linux.yml/badge.svg)](https://github.com/raku-community-modules/FastCGI/actions) [![Actions Status](https://github.com/raku-community-modules/FastCGI/actions/workflows/macos.yml/badge.svg)](https://github.com/raku-community-modules/FastCGI/actions) [![Actions Status](https://github.com/raku-community-modules/FastCGI/actions/workflows/windows.yml/badge.svg)](https://github.com/raku-community-modules/FastCGI/actions)

NAME
====

FastCGI - a FastCGI library for Raku

SYNOPSIS
========

```raku
use FastCGI;

my $fcgi = FastCGI.new( :port(9119) );

$fcgi.handle: &handler;
```

DESCRIPTION
===========

A library for building web applications using FastCGI in Raku. Uses a PSGI-compliant interface by default, so you can use it with any PSGI-compliant frameworks, such as WWW::App.

Status
------

Basic functionality works, but is currently fairly slow using the pure source implementation of the FastCGI protocol.

I haven't done any extensive testing using input streams or error streams.

Example
-------

Currently the use of the `handler` call is required. More advanced use, such as with the new SCGI is planned, but will require some significant refactoring.

```raku
use FastCGI;

my $fcgi = FastCGI.new( :port(9119) );

my $handler = sub (%env) {
    my $name = %env<QUERY_STRING> || 'World';
    my $status = '200';
    my @headers = 'Content-Type' => 'text/plain';
    my @body = "Hello $name\n";;
    [ $status, @headers, @body ]
}

$fcgi.handle: $handler;
```

TODO
----

  * Test the STDIN and STDERR streams.

  * Rename FastCGI::Protocol to FastCGI::Protocol:PP

  * Add FastCGI::Protocol::NativeCall as a wrapper to libfcgi

  * Write new FastCGI::Protocol wrapper that uses either PP or NativeCall

  * Refactor the Connection/Request code to allow for custom request loops.

AUTHOR
======

Timothy Totten

COPYRIGHT AND LICENSE
=====================

Copyright 2013 - 2016 Timothy Totten

Copyright 2017 - 2026 Raku Community

This library is free software; you can redistribute it and/or modify it under the Artistic License 2.0.

