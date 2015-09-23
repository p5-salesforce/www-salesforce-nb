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

done_testing();
