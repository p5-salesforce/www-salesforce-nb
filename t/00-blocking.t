use Mojo::Base -strict;
BEGIN {
	$ENV{MOJO_NO_SOCKS} = $ENV{MOJO_NO_TLS} = 1;
	$ENV{MOJO_REACTOR} = 'Mojo::Reactor::Poll';
}

use Test::More;
use Mojo::JSON;
use Mojolicious::Lite;
use Data::Dumper;
use Try::Tiny;

use FindBin;
use lib "$FindBin::Bin/lib";

BEGIN {
	use_ok( 'WWW::Salesforce' ) || print "Bail out!\n";
}
# Silence
app->log->level('fatal');
get '/' => {text => 'works!'};
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
post '/services/oauth2/token' => sub {
	my $c = shift;
	$c->render(json => {instance_url=>Mojo::URL->new('/'),issued_at=>time()*1000,access_token => '123455663452abacbabababababababanenenenene'});
};


my $sf = WWW::Salesforce->new(version=>'33.0');
isa_ok( $sf, 'WWW::Salesforce', 'Is a proper Salesforce object' );

# Test attributes
can_ok($sf, qw(_access_token _access_time _instance_url consumer_key consumer_secret username password pass_token ua version login_url) );

# force the URL to point to our mock-server
$sf->login_url(Mojo::URL->new('/'));

# Test UA
is $sf->ua->get('/')->res->code, 200, 'UA: right status';
is $sf->ua->get('/')->res->body, 'works!', 'UA: right body content';

# Test API Path gathering
is($sf->_path(),'/services/data/v33.0/','api_path: got the correct latest path');

# Test Login attempt
is($sf->login()->_access_token(), '123455663452abacbabababababababanenenenene', 'login: got the right access token');

# Test a simple query
{
	my $res = $sf->query('select Id,IsActive,Name from Product2');
	isa_ok($res,'ARRAY',"query: got back an array ref");
	is( scalar(@{$res}), 2, 'query: got back 2 results');
	is( $res->[0]{Id}, '01t500000016RuaAAE', 'query: first result has proper ID' );
	is( $res->[1]{Id}, '01t500000016RuaAAF', 'query: second result has proper ID' );
}

# Test error handling
{
	my $error = try {
		$sf->query('bad query');
	}
	catch {
		$_;
	};
	like($error, qr/^401 Unauthorized: foo: what?!?/, 'error handling: got proper error message');
}

done_testing();
