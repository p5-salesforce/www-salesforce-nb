use Mojo::Base -strict;
use Test::More;
use Mojo::JSON;
use Try::Tiny;
use v5.10;

use FindBin;
use lib "$FindBin::Bin/lib";

BEGIN {
	use_ok( 'WWW::Salesforce' ) || BAIL_OUT("Can't use WWW::Salesforce");
}

my $sf = try {
	WWW::Salesforce->new(
		login_url => Mojo::URL->new('/'),
		login_type => 'oauth2_up',
		version => '33.0',
		username => 'test',
		password => 'test',
		pass_token => 'toke',
		consumer_key => 'test_id',
		consumer_secret => 'test_secret',
	);
} catch {
	BAIL_OUT("Unable to create new instance: $_");
	return undef;
};
isa_ok( $sf, 'WWW::Salesforce', 'Is a proper Salesforce object' ) || BAIL_OUT("can't instantiate");

# Test attributes
can_ok($sf, (
	qw(_access_token _access_time _instance_url consumer_key consumer_secret ),
	qw(username password pass_token ua version login_url login_type),
)) or BAIL_OUT("Something's wrong with the attributes!");

# Test API Path gathering
is($sf->_path(),'/services/data/v33.0/','api_path: got the correct path');
is($sf->_path('soap'),'/services/Soap/u/33.0/','api_path: got the correct soap path');
is($sf->_path('invalid'),'/services/data/v33.0/','api_path: got the correct path with an invalid option');

# test headers
{
	my $expected = {Accept=>'application/json',DNT=>1,'Sforce-Query-Options'=>'batchSize=2000','Accept-Charset'=>'UTF-8'};
	my $expected_soap = {Accept=>'text/xml','Content-Type'=>'text/xml; charset=utf-8',SOAPAction=>'""',Expect=>'100-continue',DNT=>1,'Sforce-Query-Options'=>'batchSize=2000','Accept-Charset'=>'UTF-8'};
	is_deeply($sf->_headers(), $expected, "headers: Correct json headers for not being logged in.");
	is_deeply($sf->_headers('badType'), $expected, "headers: Correct json headers not logged in, invalid type");
	is_deeply($sf->_headers('soap'), $expected_soap, "headers: Correct soap headers for not being logged in.");
	#test soap with instance url --coverage
	$sf->_instance_url('https://www.bar.com');
	$expected_soap->{Host} = 'www.bar.com';
	is_deeply($sf->_headers('soap'), $expected_soap, "headers: soap, not loggedin, _instance_url");
	$sf->_instance_url('');
	$sf->login_url('https://www.bar.com');
	is_deeply($sf->_headers('soap'), $expected_soap, "headers: soap, not loggedin, login_url");
	delete($expected_soap->{Host});
	$sf->_instance_url('');
	$sf->login_url('');
	is_deeply($sf->_headers('soap'), $expected_soap, "headers: soap, not loggedin, no urls for host header");
}

# basic error string responses
is($sf->_error(),'Unknown error.',"_error: empty call");
is($sf->_error(undef),'Unknown error.',"_error: undef");
is($sf->_error(''),'Unknown error.',"_error: empty string");
is($sf->_error('error string'), 'error string', "_error: string error");
is($sf->_error([]), 'Invalid transaction object', "_error: arrayref");
is($sf->_error({}), 'Invalid transaction object', "_error: hashref");
is($sf->_error($sf), 'Invalid transaction object', "_error: non-Transaction object");

# SOAP error messages
{
	my $res = Mojo::Message::Response->new->error({code=>500, message=>'Internal Server Error'});
	$res->headers->content_type('text/xml;charset=UTF-8');
	$res->body(q(<?xml version="1.0" encoding="UTF-8"?><soapenv:Envelope xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/" xmlns:sf="urn:fault.partner.soap.sforce.com" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"><soapenv:Body><soapenv:Fault><faultcode>INVALID_LOGIN</faultcode><faultstring>INVALID_LOGIN: Invalid username, password, security token; or user locked out.</faultstring><detail><sf:LoginFault xsi:type="sf:LoginFault"><sf:exceptionCode>INVALID_LOGIN</sf:exceptionCode><sf:exceptionMessage>Invalid username, password, security token; or user locked out.</sf:exceptionMessage></sf:LoginFault></detail></soapenv:Fault></soapenv:Body></soapenv:Envelope>));
	is(
		$sf->_error(Mojo::Transaction::HTTP->new->res($res)),
		'500 Internal Server Error, INVALID_LOGIN: INVALID_LOGIN: Invalid username, password, security token; or user locked out.',
		"_error: SOAP error"
	);

	$res = Mojo::Message::Response->new->error({code=>500, message=>'Internal Server Error'});
	$res->headers->content_type('text/xml;charset=UTF-8');
	$res->body(q(<?xml version="1.0" encoding="UTF-8"?><soapenv:Envelope xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/" xmlns:sf="urn:fault.partner.soap.sforce.com" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"><soapenv:Body><soapenv:Fault><faultcode></faultcode><faultstring></faultstring></soapenv:Fault></soapenv:Body></soapenv:Envelope>));
	is(
		$sf->_error(Mojo::Transaction::HTTP->new->res($res)),
		'500 Internal Server Error',
		"_error: SOAP error with empty strings"
	);

	$res = Mojo::Message::Response->new->error({code=>500, message=>'Internal Server Error'});
	$res->headers->content_type('text/xml;charset=UTF-8');
	$res->body(q(<?xml version="1.0" encoding="UTF-8"?><soapenv:Envelope xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/" xmlns:sf="urn:fault.partner.soap.sforce.com" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"><soapenv:Body><soapenv:Fault><faultstring>test</faultstring></soapenv:Fault></soapenv:Body></soapenv:Envelope>));
	is(
		$sf->_error(Mojo::Transaction::HTTP->new->res($res)),
		'500 Internal Server Error, test',
		"_error: SOAP error with no faultcode"
	);

	$res = Mojo::Message::Response->new->error({code=>500, message=>'Internal Server Error'});
	$res->headers->content_type('text/xml;charset=UTF-8');
	$res->body(q(<?xml version="1.0" encoding="UTF-8"?><soapenv:Envelope xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/" xmlns:sf="urn:fault.partner.soap.sforce.com" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"><soapenv:Body><soapenv:Fault><faultcode>test</faultcode></soapenv:Fault></soapenv:Body></soapenv:Envelope>));
	is(
		$sf->_error(Mojo::Transaction::HTTP->new->res($res)),
		'500 Internal Server Error, test',
		"_error: SOAP error with no faultstring"
	);

	$res = Mojo::Message::Response->new->error({code=>500, message=>'Internal Server Error'});
	$res->headers->content_type('text/xml;charset=UTF-8');
	$res->body(q(<?xml version="1.0" encoding="UTF-8"?><soapenv:Envelope xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/" xmlns:sf="urn:fault.partner.soap.sforce.com" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"><soapenv:Body><soapenv:Fault></soapenv:Fault></soapenv:Body></soapenv:Envelope>));
	is(
		$sf->_error(Mojo::Transaction::HTTP->new->res($res)),
		'500 Internal Server Error',
		"_error: SOAP error with no faultcode or faultstring"
	);

	$res = Mojo::Message::Response->new->error({code=>500, message=>'Internal Server Error'});
	$res->headers->content_type('text/xml;charset=UTF-8');
	$res->body(q(<?xml version="1.0" encoding="UTF-8"?><soapenv:Envelope xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/" xmlns:sf="urn:fault.partner.soap.sforce.com" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"><soapenv:Body></soapenv:Body></soapenv:Envelope>));
	is(
		$sf->_error(Mojo::Transaction::HTTP->new->res($res)),
		'500 Internal Server Error',
		"_error: SOAP error with no soapenv:Fault tag"
	);

	$res = Mojo::Message::Response->new->error({code=>500, message=>'Internal Server Error'});
	$res->headers->content_type('text/xml;charset=UTF-8');
	$res->body(q(foooo));
	is(
		$sf->_error(Mojo::Transaction::HTTP->new->res($res)),
		'500 Internal Server Error',
		"_error: SOAP error with malformed XML - No DOM"
	);
}

# JSON error responses
{
	my $res = Mojo::Message::Response->new->error({code=>400, message=>'Bad Request'});
	$res->headers->content_type('application/json');
	$res->body(q({"error": "unsupported_grant_type","error_description": "grant type not supported"}));
	is(
		$sf->_error(Mojo::Transaction::HTTP->new->res($res)),
		'400 Bad Request, unsupported_grant_type: grant type not supported',
		"_error: JSON error as hash with error/error_description"
	);

	$res = Mojo::Message::Response->new->error({code=>400, message=>'Bad Request'});
	$res->headers->content_type('application/json');
	$res->body(q({"errorCode": "unsupported_grant_type","message": "grant type not supported"}));
	is(
		$sf->_error(Mojo::Transaction::HTTP->new->res($res)),
		'400 Bad Request, unsupported_grant_type: grant type not supported',
		"_error: JSON error as hash with errorCode/message"
	);

	$res = Mojo::Message::Response->new->error({code=>400, message=>'Bad Request'});
	$res->headers->content_type('application/json');
	$res->body(q({"error": "","error_description": ""}));
	is(
		$sf->_error(Mojo::Transaction::HTTP->new->res($res)),
		'400 Bad Request',
		"_error: JSON error as hash with empty strings"
	);

	$res = Mojo::Message::Response->new->error({code=>400, message=>'Bad Request'});
	$res->headers->content_type('application/json');
	$res->body(q({"error": "","error_description": "test"}));
	is(
		$sf->_error(Mojo::Transaction::HTTP->new->res($res)),
		'400 Bad Request, test',
		"_error: JSON error as hash with empty code"
	);

	$res = Mojo::Message::Response->new->error({code=>400, message=>'Bad Request'});
	$res->headers->content_type('application/json');
	$res->body(q({"error": "test","error_description": ""}));
	is(
		$sf->_error(Mojo::Transaction::HTTP->new->res($res)),
		'400 Bad Request, test',
		"_error: JSON error as hash with empty message"
	);

	$res = Mojo::Message::Response->new->error({code=>400, message=>'Bad Request'});
	$res->headers->content_type('application/json');
	$res->body(q([{"message": "A query string has to be specified","errorCode": "MALFORMED_QUERY"}]));
	is(
		$sf->_error(Mojo::Transaction::HTTP->new->res($res)),
		'400 Bad Request, MALFORMED_QUERY: A query string has to be specified',
		"_error: JSON error as array"
	);

	$res = Mojo::Message::Response->new->error({code=>400, message=>'Bad Request'});
	$res->headers->content_type('application/json');
	$res->body(q([{"error_description": "A query string has to be specified","error": "MALFORMED_QUERY"}]));
	is(
		$sf->_error(Mojo::Transaction::HTTP->new->res($res)),
		'400 Bad Request, MALFORMED_QUERY: A query string has to be specified',
		"_error: JSON error as array"
	);

	$res = Mojo::Message::Response->new->error({code=>400, message=>'Bad Request'});
	$res->headers->content_type('application/json');
	$res->body(q([{"error_description": "","error": ""}]));
	is(
		$sf->_error(Mojo::Transaction::HTTP->new->res($res)),
		'400 Bad Request',
		"_error: JSON error as array with empty strings"
	);

	$res = Mojo::Message::Response->new->error({code=>400, message=>'Bad Request'});
	$res->headers->content_type('application/json');
	$res->body(q([{"error_description": "test","error": ""}]));
	is(
		$sf->_error(Mojo::Transaction::HTTP->new->res($res)),
		'400 Bad Request, test',
		"_error: JSON error as array with empty code"
	);

	$res = Mojo::Message::Response->new->error({code=>400, message=>'Bad Request'});
	$res->headers->content_type('application/json');
	$res->body(q([{"error_description": "","error": "test"}]));
	is(
		$sf->_error(Mojo::Transaction::HTTP->new->res($res)),
		'400 Bad Request, test',
		"_error: JSON error as array with empty message"
	);
}

# superfluous testing for coverage
{
	my $res = Mojo::Message::Response->new;
	$res->headers->content_type('application/json');
	$res->body(q([{"error_description": "","error": "test"}]));
	is(
		$sf->_error(Mojo::Transaction::HTTP->new->res($res)),
		'Transaction succeeded',
		"_error: Successful TX"
	);

	$res = Mojo::Message::Response->new->error({code=>400, message=>'Bad Request'});
	$res->headers->content_type('application/json');
	$res->body(q([null,[],{"error_description": "","error": "test"}]));
	is(
		$sf->_error(Mojo::Transaction::HTTP->new->res($res)),
		'400 Bad Request, test',
		"_error: JSON arrayref, two invalid array items"
	);

	$res = Mojo::Message::Response->new->error({code=>400, message=>'Bad Request'});
	$res->headers->content_type('application/json');
	$res->body('');
	is(
		$sf->_error(Mojo::Transaction::HTTP->new->res($res)),
		'400 Bad Request',
		"_error: Errored TX, empty body"
	);

	$res = Mojo::Message::Response->new->error({code=>400, message=>'Bad Request'});
	$res->headers->content_type('text/plain');
	$res->body('Some Error!');
	is(
		$sf->_error(Mojo::Transaction::HTTP->new->res($res)),
		'400 Bad Request, Some Error!',
		"_error: Errored TX, plaintext body"
	);

	$res = Mojo::Message::Response->new->error({code=>0, message=>'Custom error'});
	$res->headers->content_type('text/plain');
	$res->body('  ');
	is(
		$sf->_error(Mojo::Transaction::HTTP->new->res($res)),
		'500 Custom error',
		"_error: Errored TX, custom error"
	);

	$res = Mojo::Message::Response->new->error({code=>0, message=>''});
	$res->headers->content_type('text/plain');
	$res->body('  ');
	is(
		$sf->_error(Mojo::Transaction::HTTP->new->res($res)),
		'500',
		"_error: Errored TX, custom error - no msg"
	);

	$res = Mojo::Message::Response->new->error({code=>0, message=>''});
	$res->body('  ');
	is(
		$sf->_error(Mojo::Transaction::HTTP->new->res($res)),
		'500',
		"_error: Errored TX, custom error - No Content Type"
	);
}

done_testing();
