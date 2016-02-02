use Mojo::Base -strict;
use Test::More;
use Mojo::IOLoop;
use Mojolicious;
use Try::Tiny;
use v5.10;

use FindBin;
use lib "$FindBin::Bin/lib";

BEGIN { use_ok( 'WWW::Salesforce' ) || BAIL_OUT("Can't use WWW::Salesforce"); }

my $sf = try { WWW::Salesforce->new(); } catch { BAIL_OUT("Unable to create new instance: $_"); };
isa_ok( $sf, 'WWW::Salesforce', 'Is a proper Salesforce object' ) || BAIL_OUT("can't instantiate");

# setup mock
my $mock = Mojolicious->new;
$mock->log->level('fatal');
$mock->routes->post('/services/Soap/u/33.0/' => sub {
	my $c = shift;
	my $username = '';
	my $password = '';
	my $input = '';
	my $type = $c->req->headers->header('Content-Type') || '';
	# return an error if the content-type header isn't correct.
	my $ehead = q(<?xml version="1.0" encoding="UTF-8"?><soapenv:Envelope xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/"><soapenv:Body><soapenv:Fault><faultcode>soapenv:Client</faultcode><faultstring>content-type of the request should be text/xml</faultstring></soapenv:Fault></soapenv:Body></soapenv:Envelope>);
	return $c->render(data=>$ehead, format => 'xml', status=>500) unless $type =~ /text\/xml/;

	my $eof = q(<?xml version="1.0" encoding="UTF-8"?><soapenv:Envelope xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/"><soapenv:Body><soapenv:Fault><faultcode>soapenv:Client</faultcode><faultstring>Premature end of file.</faultstring></soapenv:Fault></soapenv:Body></soapenv:Envelope>);
	$input = $c->req->dom() if $c->req && $c->req->content && $c->req->dom;
	return $c->render(data=>$eof, format => 'xml', status=>500) unless $input;

	$username = $input->at('urn\:username')->text() if $input->at('urn\:username');
	$password = $input->at('urn\:password')->text() if $input->at('urn\:password');
	#return actual error messages
	my $error=q(<?xml version="1.0" encoding="UTF-8"?><soapenv:Envelope xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/" xmlns:sf="urn:fault.partner.soap.sforce.com" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"><soapenv:Body><soapenv:Fault><faultcode>sf:INVALID_LOGIN</faultcode><faultstring>INVALID_LOGIN: Invalid username, password, security token; or user locked out.</faultstring><detail><sf:LoginFault xsi:type="sf:LoginFault"><sf:exceptionCode>INVALID_LOGIN</sf:exceptionCode><sf:exceptionMessage>Invalid username, password, security token; or user locked out.</sf:exceptionMessage></sf:LoginFault></detail></soapenv:Fault></soapenv:Body></soapenv:Envelope>);
	return $c->render(data=>$error, format => 'xml', status=>500) unless $username eq 'test';
	return $c->render(data=>$error, format => 'xml', status=>500) unless $password eq 'testtoke';
	# return the successful response
	my $success=qq(<?xml version="1.0" encoding="UTF-8"?><soapenv:Envelope xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/" xmlns="urn:partner.soap.sforce.com" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"><soapenv:Body><loginResponse><result><metadataServerUrl>/</metadataServerUrl><passwordExpired>false</passwordExpired><sandbox>false</sandbox><serverUrl>/</serverUrl><sessionId>123455663452abacbabababababababanenenenene</sessionId><userId>00e30658AA0de34AA2</userId><userInfo><accessibilityMode>false</accessibilityMode><currencySymbol>\$</currencySymbol><orgAttachmentFileSizeLimit>5242880</orgAttachmentFileSizeLimit><orgDefaultCurrencyIsoCode>USD</orgDefaultCurrencyIsoCode><orgDisallowHtmlAttachments>false</orgDisallowHtmlAttachments><orgHasPersonAccounts>false</orgHasPersonAccounts><organizationId>00e30658AA0de34AAX</organizationId><organizationMultiCurrency>false</organizationMultiCurrency><organizationName>Test Company</organizationName><profileId>00e30658AA0de34AAA</profileId><roleId>00e30658AA0de34AA1</roleId><sessionSecondsValid>14400</sessionSecondsValid><userDefaultCurrencyIsoCode xsi:nil="true"/><userEmail>test\@tester.com</userEmail><userFullName>Test User</userFullName><userId>00e30658AA0de34AA2</userId><userLanguage>en_US</userLanguage><userLocale>en_US</userLocale><userName>$username</userName><userTimeZone>America/New_York</userTimeZone><userType>Standard</userType><userUiSkin>Theme3</userUiSkin></userInfo></result></loginResponse></soapenv:Body></soapenv:Envelope>);
	return $c->render(data => $success, format => 'xml');
});
$mock->routes->post('/services/oauth2/revoke' => sub {
	my $c = shift;
	my $token = $c->param('token');
	return $c->render(json=>[{error_description=>"invalid token: $token",error=>"unsupported_token_type"}], status=>400) unless $token eq '123455663452abacbabababababababanenenenene';
	return $c->render(json=>[{success=>'true'}]);
});
$mock->routes->post('/services/oauth2/token' => sub {
	my $c = shift;
	my $grant_type = $c->param('grant_type') || '';
	my $client_id = $c->param('client_id') || '';
	my $client_secret = $c->param('client_secret') || '';
	my $username = $c->param('username') || '';
	my $password = $c->param('password') || '';
	#return actual error messages
	return $c->render(json=>[{error_description=>"grant type not supported",error=>"unsupported_grant_type"}], status=>400) unless $grant_type eq 'password';
	return $c->render(json=>[{error_description=>'Invalid client credentials',error=>'invalid_client'}], status=>400) unless $client_id eq 'test_id';
	return $c->render(json=>[{error_description=>'Invalid client credentials',error=>'invalid_client'}], status=>400) unless $client_secret eq 'test_secret';
	return $c->render(json=>[{error_description=>'authentication failure',error=>'invalid_grant'}], status=>400) unless $username eq 'test';
	return $c->render(json=>[{error_description=>'authentication failure',error=>"invalid_grant"}], status=>400) unless $password eq 'testtoke';
	# return the successful response
	return $c->render(json => {
		id => "/id/00D3012300VnRVAU/0015004310HWV5ZAQ",
		token_type =>"Bearer",
		signature => "CtSomeSignature3421351345141LKJFSDLK8723451nhx8=",
		instance_url => Mojo::URL->new('/'),
		issued_at => time()*1000,
		access_token => '123455663452abacbabababababababanenenenene'
	});
});
$sf->ua->server->app($mock); #point the client to the mock

# set the login
$sf->version('33.0');
$sf->login_url(Mojo::URL->new('/'));
$sf->login_type('oauth2_up');
$sf->username('test');
$sf->password('test');
$sf->pass_token('toke');
$sf->consumer_key('test_id');
$sf->consumer_secret('test_secret');
# actual testing
can_ok($sf, qw(login)) or BAIL_OUT("Something's wrong with the methods!");

# test a bad login
{
	my $res;
	$res = try { $sf->login() } catch {$_};
	isa_ok($res,'WWW::Salesforce',"login: empty call, proper response");
	is( $sf->_access_token(), '123455663452abacbabababababababanenenenene', 'login: Empty call, proper response' );
	$sf->_access_token('');
	$res = try { $sf->login('') } catch {$_};
	isa_ok($res,'WWW::Salesforce',"login: empty string call, proper response");
	is( $sf->_access_token(), '123455663452abacbabababababababanenenenene', 'login: Empty string call, proper response' );
	$sf->_access_token('');
	$res = try { $sf->login({}) } catch {$_};
	isa_ok($res,'WWW::Salesforce',"login: hashref call, proper response");
	is( $sf->_access_token(), '123455663452abacbabababababababanenenenene', 'login: hashref call, proper response' );
	$sf->_access_token('');

	$res = try {
		$sf->login_type('oauth2_up');
		$sf->username('test2');
		$sf->login();
	}
	catch {
		$_;
	};
	like($res, qr/invalid_grant/, 'oauth2 login error: got proper error message');

	$res = try {
		$sf->login_type('soap');
		$sf->username('test2');
		$sf->login();
	}
	catch {
		$_;
	};
	like($res, qr/INVALID_LOGIN/, 'soap login error: got proper error message');
}

# OATH2_UP Test Login attempt
try {
	$sf->login_type('oauth2_up');
	$sf->username('test');
	$sf->login();
	is($sf->_access_token(), '123455663452abacbabababababababanenenenene', 'login: oauth2_up: got the right access token');
	$sf->_access_token('');
} catch {
	BAIL_OUT("Unable to login and out properly with oauth2_up: $_");
};

# SOAP login
try {
	$sf->login_type('soap');
	$sf->login();
	is($sf->_access_token(), '123455663452abacbabababababababanenenenene', 'login: soap: got the right access token');
	$sf->_access_token('');
} catch {
	BAIL_OUT("Unable to login and out properly with soap: $_");
};

# non-blocking errors
{
	my ($err,$res);
	Mojo::IOLoop->delay(
		sub {$sf->login_type('oauth2_up');$sf->username('test2');$sf->login(shift->begin(0));},
		sub { (undef, undef, $err, $res) = @_;}
	)->catch(sub {BAIL_OUT("Something went wrong in login_oath2_up-nb: ".pop)})->wait;
	like( $err, qr/invalid_grant/, 'login-nb oauth2_up: error: invalid grant');
	is($res, undef, 'login-nb oauth2_up: error: correctly got no successful response');
	$err = undef;
	$res = undef;
	Mojo::IOLoop->delay(
		sub {$sf->login_type('soap');$sf->username('test2');$sf->login(shift->begin(0));},
		sub { (undef, undef, $err, $res) = @_;}
	)->catch(sub {BAIL_OUT("Something went wrong in login_soap-nb: ".pop)})->wait;
	like( $err, qr/INVALID_LOGIN/, 'login-nb soap: error: invalid login');
	is($res, undef, 'login-nb soap: error: correctly got no successful response');
}

# non-blocking successes
{
	my ($err,$res);
	Mojo::IOLoop->delay(
		sub {$sf->login_type('oauth2_up');$sf->username('test');$sf->login(shift->begin(0));},
		sub { (undef, undef, $err, $res) = @_;}
	)->catch(sub {BAIL_OUT("Something went wrong in login_soap-nb: ".pop)})->wait;
	is( $err, undef, 'login-nb oauth2_up: login success with no error');
	is($res, '123455663452abacbabababababababanenenenene', 'login-nb oauth2_up: successful login');
	$sf->_access_token('');
	$sf->_instance_url('');
	$err = undef;
	$res = undef;

	Mojo::IOLoop->delay(
		sub {$sf->login_type('soap');$sf->login(shift->begin(0));},
		sub { (undef, undef, $err, $res) = @_;}
	)->catch(sub {BAIL_OUT("Something went wrong in login_soap-nb: ".pop)})->wait;
	is( $err, undef, 'login-nb soap: login success with no error');
	is($res, '123455663452abacbabababababababanenenenene', 'login-nb soap: successful login');
	$sf->_access_token('');
}
done_testing();
