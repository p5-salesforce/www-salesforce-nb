use Mojo::Base -strict;
use Test::More;
use Mojo::JSON;
use Try::Tiny;
use v5.10;

use FindBin;
use lib "$FindBin::Bin/lib";

BEGIN {
	use_ok( 'WWW::Salesforce::SOAP' ) || BAIL_OUT("Can't use WWW::Salesforce");
}

# Test attributes
can_ok('WWW::Salesforce::SOAP', (
	qw(envelope envelope_login response_login)
)) or BAIL_OUT("Something's wrong with the functions");

my $envelope = q(<?xml version="1.0" encoding="utf-8"?><soapenv:Envelope xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/" xmlns:urn="urn:partner.soap.sforce.com"><soapenv:Header /><soapenv:Body /></soapenv:Envelope>);
my $envelope_login = q(<?xml version="1.0" encoding="utf-8"?><soapenv:Envelope xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/" xmlns:urn="urn:partner.soap.sforce.com"><soapenv:Body><urn:login><urn:username /><urn:password /></urn:login></soapenv:Body></soapenv:Envelope>);
is(WWW::Salesforce::SOAP::envelope(), $envelope, "envelope: got the right string back");
is(WWW::Salesforce::SOAP::envelope_login(), $envelope_login, "envelope_login: got the right string back");
done_testing();
