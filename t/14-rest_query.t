use Mojo::Base -strict;
use Test::More;
use Mojo::IOLoop::Delay;
use Mojo::JSON;
use Mojolicious::Lite;
use Try::Tiny;
use v5.10;

use FindBin;
use lib "$FindBin::Bin/lib";

BEGIN {
	$ENV{MOJO_NO_SOCKS} = $ENV{MOJO_NO_TLS} = 1;
	$ENV{MOJO_REACTOR} = 'Mojo::Reactor::Poll';
	use_ok( 'WWW::Salesforce' ) || BAIL_OUT("Can't use WWW::Salesforce");
}
# Silence
app->log->level('fatal');
get '/services/data/v33.0/query' => sub {
	my $c = shift;
	my $query = $c->param('q');
	if ( $query eq 'select Id,IsActive,Name from Product2' ) {
		return $c->render(json => {done=>0,nextRecordsUrl=>'/services/data/v33.0/query/test123',records=>[
			{
				Id=>'01t500000016RuaAAE',
				IsActive=>1,
				Name=>'Test Name',
				attributes=>{
					type=>'Product2',
					url=>'/services/data/v33.0/sobjects/Product2/01t500000016RuaAAE',
				},
			},
		],});
	}
	$c->render(json=>[{errorCode=>'foo',message=>'what?!?'}], status=>401);
};
get '/services/data/v33.0/query/test123' => sub {
	my $c = shift;
	return $c->render(json => {done=>1,records=>[
		{
			Id=>'01t500000016RuaAAF',
			IsActive=>1,
			Name=>'Test Name 2',
			attributes=>{
				type=>'Product2',
				url=>'/services/data/v33.0/sobjects/Product2/01t500000016RuaAAF',
			},
		},
	],});
};

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
# set the login
$sf->_instance_url('/');
$sf->_access_token('123455663452abacbabababababababanenenenene');
$sf->_access_time(time());
# actual testing
can_ok($sf, qw(query) );

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

done_testing;
