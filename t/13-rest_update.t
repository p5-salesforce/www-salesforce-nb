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

my $ID = '001W000000KY0vBIAT';
my $ID_DEL = '001W000000KY0vBIAC';
my $ID_MAL = '001W000000KY0vBZZZ';
my @fields = qw(Name MailingStreet MailingCity MailingState MailingCountry Phone);
# Silence
app->log->level('fatal');
patch '/services/data/v33.0/sobjects/:type/:id' => sub {
	my $c = shift;
	my $type = $c->stash('type') || '';
	my $id = $c->stash('id') || '';
	my $params = $c->req->json || undef;
	unless ( $type eq 'Account' ) {
		return $c->render(status=>404,json=>[{errorCode=> "NOT_FOUND", message=>"The requested resource does not exist"}]);
	}
	if ( $id eq $ID_DEL ) {
		return $c->render(status=>404,json=>[{errorCode=> "ENTITY_IS_DELETED", message=>"entity is deleted",fields=>[],}]);
	}
	elsif ( $id eq $ID_MAL ) {
		return $c->render(status=>400,json=>[{errorCode=> "MALFORMED_ID", message=>"Account ID: id value of incorrect type: $id",fields=>["Id",],}]);
	}
	elsif ( $id ne $ID ) {
		return $c->render(status=>404,json=>[{errorCode=> "NOT_FOUND", message=>"Provided external ID field does not exist or is not accessible: $id"}]);
	}
	unless ( $params && ref($params) ) {
		return $c->render(json=>[{message=>"The HTTP entity body is required, but this request has no entity body.",errorCode=>"JSON_PARSER_ERROR"}],status=>400);
	}
	unless ( ref($params) eq 'HASH' ) {
		return $c->render(json=>[{message=>"Can not deserialize SObject out of START_ARRAY token at [line:1, column:1]",errorCode=>"JSON_PARSER_ERROR"}],status=>400);
	}
	for my $key (keys %$params) {
		unless ( grep {$key eq $_} @fields ) {
			return $c->render(json=>[{message=>"No such column '$key' on sobject of type $type",errorCode=>"INVALID_FIELD"}],status=>400);
		}
	}
	# success is nothing
	return $c->render(status=>204,text=>'');
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
# set the login
$sf->_instance_url('/');
$sf->_access_token('123455663452abacbabababababababanenenenene');
$sf->_access_time(time());
# actual testing
isa_ok( $sf, 'WWW::Salesforce', 'Is a proper Salesforce object' ) || BAIL_OUT("can't instantiate");

can_ok($sf, qw(update) );

done_testing;
