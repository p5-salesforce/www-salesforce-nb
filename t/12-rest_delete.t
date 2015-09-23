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

# Silence
app->log->level('fatal');
del '/services/data/v33.0/sobjects/:type/:id' => sub {
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
	$error = try {return $sf->delete(undef, $ID) } catch { $_; };
	like( $error, qr/No SObject Type defined/, 'delete error: undef type');
	$error = try {return $sf->del(undef, $ID) } catch { $_; };
	like( $error, qr/No SObject Type defined/, 'del error: undef type');
	$error = try {return $sf->destroy(undef, $ID) } catch { $_; };
	like( $error, qr/No SObject Type defined/, 'destroy error: undef type');
	# all defined, bad type
	$error = try {return $sf->delete('badObject', $ID) } catch { $_; };
	like( $error, qr/The requested resource does not exist/, 'delete error: invalid object type');
	$error = try {return $sf->del('badObject', $ID) } catch { $_; };
	like( $error, qr/The requested resource does not exist/, 'del error: invalid object type');
	$error = try {return $sf->destroy('badObject', $ID) } catch { $_; };
	like( $error, qr/The requested resource does not exist/, 'destroy error: invalid object type');
	# empty ID
	$error = try {return $sf->delete('badObject') } catch { $_; };
	like( $error, qr/No SObject ID provided/, 'delete error: empty ID');
	$error = try {return $sf->del('badObject') } catch { $_; };
	like( $error, qr/No SObject ID provided/, 'del error: empty ID');
	$error = try {return $sf->destroy('badObject') } catch { $_; };
	like( $error, qr/No SObject ID provided/, 'destroy error: empty ID');
	# undef ID
	$error = try {return $sf->delete('badObject',undef) } catch { $_; };
	like( $error, qr/No SObject ID provided/, 'delete error: undef ID');
	$error = try {return $sf->del('badObject',undef) } catch { $_; };
	like( $error, qr/No SObject ID provided/, 'del error: undef ID');
	$error = try {return $sf->destroy('badObject',undef) } catch { $_; };
	like( $error, qr/No SObject ID provided/, 'destroy error: undef ID');
	# invalid ID
	$error = try {return $sf->delete('badObject','1234') } catch { $_; };
	like( $error, qr/No SObject ID provided/, 'delete error: invalid ID');
	$error = try {return $sf->del('badObject','1234') } catch { $_; };
	like( $error, qr/No SObject ID provided/, 'del error: invalid ID');
	$error = try {return $sf->destroy('badObject','1234') } catch { $_; };
	like( $error, qr/No SObject ID provided/, 'destroy error: invalid ID');
	# already deleted
	$error = try {return $sf->delete('Account',$ID_DEL) } catch { $_; };
	like( $error, qr/entity is deleted/, 'delete error: Entity is Deleted');
	$error = try {return $sf->del('Account',$ID_DEL) } catch { $_; };
	like( $error, qr/entity is deleted/, 'del error: Entity is Deleted');
	$error = try {return $sf->destroy('Account',$ID_DEL) } catch { $_; };
	like( $error, qr/entity is deleted/, 'destroy error: Entity is Deleted');
	# malformed ID
	$error = try {return $sf->delete('Account',$ID_MAL) } catch { $_; };
	like( $error, qr/malformed id/, 'delete error: Entity is malformed');
	$error = try {return $sf->del('Account',$ID_MAL) } catch { $_; };
	like( $error, qr/malformed id/, 'del error: Entity is malformed');
	$error = try {return $sf->destroy('Account',$ID_MAL) } catch { $_; };
	like( $error, qr/malformed id/, 'destroy error: Entity is malformed');
}

my $expected={id=>$ID,success=>1,errors=>[],};

# successes
{
	my $res;
	$res = try {return $sf->del('Account',$ID) }catch{$_};
	is_deeply($res, $expected, "del: type_in_object: got a good response");
	$res = try {return $sf->destroy('Account',$ID) }catch{$_};
	is_deeply($res, $expected, "destroy: type_in_object: got a good response");
	$res = try {return $sf->delete('Account',$ID) }catch{$_};
	is_deeply($res, $expected, "delete: type_in_object: got a good response");
}

# non-blocking error
Mojo::IOLoop::Delay->new()->steps(
	sub {$sf->delete('badObject',$ID, shift->begin(0));},
	sub { my ($delay, $sf, $err, $res) = @_;
		like( $err, qr/The requested resource does not exist/, 'delete-nb error: invalid object type');
		is($res, undef, 'delete-nb error: correctly got no successful response');
	}
)->catch(sub {
	shift->ioloop->stop;
	BAIL_OUT("Something went wrong in delete-nb: ".pop);
})->wait;

#non-blocking success
Mojo::IOLoop::Delay->new()->steps(
	sub {$sf->delete('Account',$ID, shift->begin(0));},
	sub {
		my ($delay, $sf, $err, $res) = @_;
		is($err, undef, 'delete-nb: correctly got no fault');
		isa_ok($res, 'HASH', 'delete-nb: got a hashref response');
		is_deeply($res, $expected, "delete-nb: got the right result");
	}
)->catch(sub {
	shift->ioloop->stop;
	BAIL_OUT("Something went wrong in delete-nb: ".pop);
})->wait;

done_testing;
