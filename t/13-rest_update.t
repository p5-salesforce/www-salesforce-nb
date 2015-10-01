use Mojo::Base -strict;
use Test::More;
use Mojo::IOLoop;
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
		return $c->render(status=>400,json=>[{errorCode=> "MALFORMED_ID", message=>"Account ID: : $id",fields=>["Id",],}]);
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
isa_ok( $sf, 'WWW::Salesforce', 'Is a proper Salesforce object' ) || BAIL_OUT("can't instantiate");
# set the login
$sf->_instance_url('/');
$sf->_access_token('123455663452abacbabababababababanenenenene');
$sf->_access_time(time());
# actual testing
can_ok($sf, qw(update) );

{ # error handling from within the PM. never hits the server
	my $error;
	# all the ways a type could fail
	$error = try {return $sf->update() } catch { $_; };
	like( $error, qr/No SObject Type defined/, 'update error: empty call, type errors first');
	$error = try {return $sf->update(undef) } catch { $_; };
	like( $error, qr/No SObject Type defined/, 'update error: undef Type');
	$error = try {return $sf->update('') } catch { $_; };
	like( $error, qr/No SObject Type defined/, 'update error: empty string Type');
	$error = try {return $sf->update({}) } catch { $_; };
	like( $error, qr/No SObject Type defined/, 'update error: hashref Type');
	$error = try {return $sf->update([]) } catch { $_; };
	like( $error, qr/No SObject Type defined/, 'update error: arrayref Type');
	# all the ways an ID could fail
	$error = try {return $sf->update('Type') } catch { $_; };
	like( $error, qr/No SObject ID provided/, 'update error: Type only, ID errors first');
	$error = try {return $sf->update('Type',undef) } catch { $_; };
	like( $error, qr/No SObject ID provided/, 'update error: undef ID');
	$error = try {return $sf->update('Type','') } catch { $_; };
	like( $error, qr/No SObject ID provided/, 'update error: empty string ID');
	$error = try {return $sf->update('Type',{}) } catch { $_; };
	like( $error, qr/No SObject ID provided/, 'update error: hashref ID');
	$error = try {return $sf->update('Type',[]) } catch { $_; };
	like( $error, qr/No SObject ID provided/, 'update error: arrayref ID');
	# all the ways the object could fail
	$error = try {return $sf->update('Type',$ID) } catch { $_; };
	like( $error, qr/Empty SObjects are not allowed/, 'update error: Type and ID, SObject errors first');
	$error = try {return $sf->update('Type',$ID,undef) } catch { $_; };
	like( $error, qr/Empty SObjects are not allowed/, 'update error: undef SObject');
	$error = try {return $sf->update('Type',$ID,'') } catch { $_; };
	like( $error, qr/Empty SObjects are not allowed/, 'update error: empty string SObject');
	$error = try {return $sf->update('Type',$ID,[]) } catch { $_; };
	like( $error, qr/Empty SObjects are not allowed/, 'update error: arrayref SObject');
	$error = try {return $sf->update('Type',$ID,{}) } catch { $_; };
	like( $error, qr/Empty SObjects are not allowed/, 'update error: empty SObject');
}

{ # now test error messages coming from the server
	my $error;
	$error = try {return $sf->update('Type',$ID,{foo=>'bar'}) } catch { $_; };
	like( $error, qr/The requested resource does not exist/, 'update error: invalid type');
	$error = try {return $sf->update('Account',$ID_DEL,{foo=>'bar'}) } catch { $_; };
	like( $error, qr/entity is deleted/, 'update error: Deleted ID');
	$error = try {return $sf->update('Account',$ID_MAL,{foo=>'bar'}) } catch { $_; };
	like( $error, qr/MALFORMED_ID/, 'update error: Malformed ID');
	$error = try {return $sf->update('Account','123456789123456789',{foo=>'bar'}) } catch { $_; };
	like( $error, qr/Provided external ID field does not exist/, 'update error: ID not found');
	$error = try {return $sf->update('Account',$ID,{foo=>'bar'}) } catch { $_; };
	like( $error, qr/No such column/, 'update error: Invalid column');
}

{ # successes
	my $res = try {return $sf->update('Account',$ID,{Name=>'bar'}) } catch { $_; };
	is_deeply($res,{id=>$ID,success=>1,errors=>[],}, 'update: Successful update');
}

# non-blocking error
Mojo::IOLoop->delay(
	sub {$sf->update('badObject',$ID,{Name=>'bar'}, shift->begin(0));},
	sub { my ($delay, $sf, $err, $res) = @_;
		like( $err, qr/The requested resource does not exist/, 'update-nb error: invalid object type');
		is($res, undef, 'update-nb error: correctly got no successful response');
	}
)->catch(sub {BAIL_OUT("Something went wrong in update-nb: ".pop)})->wait;

#non-blocking success
Mojo::IOLoop->delay(
	sub {$sf->update('Account',$ID, {Name=>'bar'}, shift->begin(0));},
	sub {
		my ($delay, $sf, $err, $res) = @_;
		is($err, undef, 'update-nb: correctly got no fault');
		isa_ok($res, 'HASH', 'update-nb: got a hashref response');
		is_deeply($res, {id=>$ID,success=>1,errors=>[],}, "update-nb: got the right result");
	}
)->catch(sub {BAIL_OUT("Something went wrong in update-nb: ".pop)})->wait;

done_testing;
