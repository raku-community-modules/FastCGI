# FastCGI for Perl 6 #

A library for building web applications using FastCGI in Perl 6.
Uses a PSGI-compliant interface by default, so you can use it with
any PSGI-compliant frameworks, such as WWW::App.

## Status

Basic functionality works, but is currently fairly slow using the pure-perl
implementation of the FastCGI protocol.

I haven't done any extensive testing using input streams or error streams.

## TODO

 * Test the STDIN and STDERR streams.
 * Rename FastCGI::Protocol to FastCGI::Protocol:PP
 * Add FastCGI::Protocol::NativeCall as a wrapper to libfcgi
 * Write new FastCGI::Protocol wrapper that uses either PP or NativeCall

## Author

This was build by Timothy Totten. You can find me on #perl6 with the nickname supernovus.

## License

Artistic License 2.0

