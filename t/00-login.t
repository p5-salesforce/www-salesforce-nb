use Mojo::Base -strict;
use Test::More;
use Mojo::JSON;
use Data::Dumper;
use Try::Tiny;

use FindBin;
use lib "$FindBin::Bin/lib";

BEGIN {
	use_ok( 'WWW::Salesforce' ) || BAIL_OUT("Can't use WWW::Salesforce");
}
require_ok('mock.pl') || BAIL_OUT("Can't load the mock server");

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

# Test UA
is $sf->ua->get('/')->res->code, 200, 'UA: right status';
is $sf->ua->get('/')->res->body, 'works!', 'UA: right body content';

# Test API Path gathering
is($sf->_path(),'/services/data/v33.0/','api_path: got the correct latest path');
is($sf->_path('soap'),'/services/Soap/u/33.0/','api_path: got the correct soap path');

# test a bad login
{
	my $res = try {
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
	$sf->logout();
	is($sf->_access_token(), undef, 'logout: oauth2_up: cleared up our login');
} catch {
	BAIL_OUT("Unable to login and out properly with oauth2_up: $_");
};

# SOAP login
try {
	$sf->login_type('soap');
	$sf->login();
	is($sf->_access_token(), '123455663452abacbabababababababanenenenene', 'login: soap: got the right access token');
	$sf->logout();
	is($sf->_access_token(), undef, 'logout: soap: cleared up our login');
} catch {
	BAIL_OUT("Unable to login and out properly with soap: $_");
};

# Test a simple query
{
	my $res = try {
		$sf->query('select Id,IsActive,Name from Product2');
	}
	catch {
		$_;
	};
	isa_ok($res,'ARRAY',"query: got back an array ref");
	is( scalar(@{$res}), 2, 'query: got back 2 results');
	is( $res->[0]{Id}, '01t500000016RuaAAE', 'query: first result has proper ID' );
	is( $res->[1]{Id}, '01t500000016RuaAAF', 'query: second result has proper ID' );
	my $error = try {
		$sf->query('bad query');
	}
	catch {
		$_;
	};
	like($error, qr/^401 Unauthorized: foo: what?!?/, 'query: got proper error message');
}

done_testing();
