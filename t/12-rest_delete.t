use Mojo::Base -strict;
use Test::More;
use Mojolicious;
use Mojo::IOLoop;
use Try::Tiny;
use v5.10;

use FindBin;
use lib "$FindBin::Bin/lib";

BEGIN { use_ok( 'WWW::Salesforce' ) || BAIL_OUT("Can't use WWW::Salesforce"); }
my $ID = '001W000000KY0vBIAT';
my $ID_DEL = '001W000000KY0vBIAC';
my $ID_MAL = '001W000000KY0vBZZZ';

my $sf = try { WWW::Salesforce->new(); } catch { BAIL_OUT("Unable to create new instance: $_"); };
isa_ok( $sf, 'WWW::Salesforce', 'Is a proper Salesforce object' ) || BAIL_OUT("can't instantiate");

# setup mock
my $mock = Mojolicious->new;
$mock->log->level('fatal');
$mock->routes->delete('/services/data/v33.0/sobjects/:type/:id' => sub {
	my $c = shift;
	my $type = $c->stash('type') || '';
	my $id = $c->stash('id') || '';
	unless ( $type eq 'Account' ) {
		return $c->render(status=>404,json=>[{errorCode=> "NOT_FOUND", message=>"The requested resource does not exist"}]);
	}
	if ( $id eq $ID_DEL ) {
		return $c->render(status=>404,json=>[{errorCode=> "ENTITY_IS_DELETED", message=>"entity is deleted",fields=>[],}]);
	}
	elsif ( $id eq $ID_MAL ) {
		return $c->render(status=>400,json=>[{errorCode=> "MALFORMED_ID", message=>"malformed id $id",fields=>[],}]);
	}
	elsif ( $id eq $ID ) {
		return $c->render(status=>204,text=>'');
	}
	return $c->render(status=>404,json=>[{errorCode=> "NOT_FOUND", message=>"Provided external ID field does not exist or is not accessible: $id"}]);
});
$sf->ua->server->app($mock); #point the client to the mock

# set the login
$sf->version('33.0');
$sf->login_url(Mojo::URL->new('/'));
$sf->_instance_url('/');
$sf->_access_token('123455663452abacbabababababababanenenenene');
$sf->_access_time(time());
# actual testing
can_ok($sf, qw(delete del destroy) );

{ # error handling
	my $error;
	# empty
	$error = try {return $sf->delete() } catch { $_; };
	like( $error, qr/No SObject Type defined/, 'delete error: empty call');
	$error = try {return $sf->del() } catch { $_; };
	like( $error, qr/No SObject Type defined/, 'del error: empty call');
	$error = try {return $sf->destroy() } catch { $_; };
	like( $error, qr/No SObject Type defined/, 'destroy error: empty call');
	# undef type
	$error = try {return $sf->delete({},{}) } catch { $_; };
	like( $error, qr/No SObject Type defined/, 'delete error: invalid type and id');
	# undef type
	$error = try {return $sf->delete(undef, $ID) } catch { $_; };
	like( $error, qr/No SObject Type defined/, 'delete error: undef type');
	# all defined, bad type
	$error = try {return $sf->delete('badObject', $ID) } catch { $_; };
	like( $error, qr/The requested resource does not exist/, 'delete error: invalid object type');
	# empty ID
	$error = try {return $sf->delete('badObject') } catch { $_; };
	like( $error, qr/No SObject ID provided/, 'delete error: empty ID');
	# undef ID
	$error = try {return $sf->delete('badObject',undef) } catch { $_; };
	like( $error, qr/No SObject ID provided/, 'delete error: undef ID');
	# invalid ID
	$error = try {return $sf->delete('badObject','1234') } catch { $_; };
	like( $error, qr/No SObject ID provided/, 'delete error: invalid ID');
	# already deleted
	$error = try {return $sf->delete('Account',$ID_DEL) } catch { $_; };
	like( $error, qr/entity is deleted/, 'delete error: Entity is Deleted');
	# malformed ID
	$error = try {return $sf->delete('Account',$ID_MAL) } catch { $_; };
	like( $error, qr/malformed id/, 'delete error: Entity is malformed');
}

my $expected={id=>$ID,success=>1,errors=>[],};

# successes
{
	my $res;
	$res = try {return $sf->delete('Account',$ID) }catch{$_};
	is_deeply($res, $expected, "delete: type_in_object: got a good response");
}

{ # non-blocking error
	my ($err, $res);
	Mojo::IOLoop->delay(
		sub { $sf->delete('badObject',$ID, shift->begin(0));},
		sub { (undef, undef, $err, $res) = @_; }
	)->catch(sub {BAIL_OUT("Something went wrong in delete-nb: ".pop)})->wait;
	like( $err, qr/The requested resource does not exist/, 'delete-nb error: invalid object type');
	is($res, undef, 'delete-nb error: correctly got no successful response');

	$err = undef;
	$res = undef;
	Mojo::IOLoop->delay(
		sub { $sf->delete('',$ID, shift->begin(0));},
		sub { (undef, undef, $err, $res) = @_; }
	)->catch(sub {BAIL_OUT("Something went wrong in delete-nb: ".pop)})->wait;
	like( $err, qr/No SObject Type defined/, 'delete-nb error: invalid object type');
	is($res, undef, 'delete-nb error: correctly got no successful response');

	$err = undef;
	$res = undef;
	Mojo::IOLoop->delay(
		sub { $sf->delete('something','', shift->begin(0));},
		sub { (undef, undef, $err, $res) = @_; }
	)->catch(sub {BAIL_OUT("Something went wrong in delete-nb: ".pop)})->wait;
	like( $err, qr/No SObject ID provided/, 'delete-nb error: invalid object id');
	is($res, undef, 'delete-nb error: correctly got no successful response');

	$err = undef;
	$res = undef;
	Mojo::IOLoop->delay(
		sub { $sf->delete('Account',$ID, shift->begin(0));},
		sub { (undef, undef, $err, $res) = @_; }
	)->catch(sub {BAIL_OUT("Something went wrong in delete-nb: ".pop)})->wait;
	is($err, undef, 'delete-nb: correctly got no fault');
	is_deeply($res, $expected, "delete-nb: got the right result");
}

{ # attempt it when logins fail
	my ($err, $res);
	$sf->_access_token('');
	Mojo::IOLoop->delay(
		sub { $sf->delete('Account',$ID, shift->begin(0));},
		sub { (undef, undef, $err, $res) = @_; }
	)->catch(sub {BAIL_OUT("Something went wrong in delete-nb: ".pop)})->wait;
	like( $err, qr/404 Not Found/, 'delete-nb error: bad login');
	is($res, undef, 'delete-nb error: bad login correctly got no successful response');
}

done_testing;
