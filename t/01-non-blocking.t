use Mojo::Base -strict;
BEGIN {
	$ENV{MOJO_NO_SOCKS} = $ENV{MOJO_NO_TLS} = 1;
	$ENV{MOJO_REACTOR} = 'Mojo::Reactor::Poll';
}
use Test::More;
use Mojo::JSON;
use Mojolicious::Lite;
use Data::Dumper;

use FindBin;
use lib "$FindBin::Bin/lib";

BEGIN {
	use_ok( 'WWW::Salesforce' ) || print "Bail out!\n";
}
# Silence
app->log->level('fatal');
get '/' => {text => 'works!'};
get '/error/query' => {text=>'what?!?', status=>401};
get '/services/data' => sub {
	my $c = shift;
	$c->render(json => [
		{label=>"Winter '11",url=>"/services/data/v20.0",version=>"20.0"},
		{label=>"Spring '11",url=>"/services/data/v21.0",version=>"21.0"},
		{label=>"Summer '11",url=>"/services/data/v22.0",version=>"22.0"},
		{label=>"Spring '15",url=>"/services/data/v33.0",version=>"33.0"},
	]);
};
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
	$c->render(json=>{});
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

# force the URL to point to our mock-server
my $sf = WWW::Salesforce->new(api_host => Mojo::URL->new('/'));
isa_ok( $sf, 'WWW::Salesforce', 'Is a proper Salesforce object' );

# Test API Path gathering
is($sf->api_path(),'/services/data/v33.0/','api_path: got the correct latest path');

done_testing();
