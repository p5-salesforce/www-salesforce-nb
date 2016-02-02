use Mojo::Base -strict;
use Test::More;
use Mojo::IOLoop;
use Mojolicious;
use Try::Tiny;
use v5.10;

use FindBin;
use lib "$FindBin::Bin/lib";

BEGIN { use_ok( 'WWW::Salesforce' ) || BAIL_OUT("Can't use WWW::Salesforce"); }

my $ERROR_OUT = 0;
my $ID = '001W000000KY0vBIAT';
my $ID_DEL = '001W000000KY0vBIAC';
my $ID_MAL = '001W000000KY0vBZZZ';
my $FIELDS = [qw(Name BillingStreet BillingCity BillingState BillingCountry Phone)];
my $RECORD_FIELDS = {
	attributes => {
		type => "Account",
		url => "/services/data/v34.0/sobjects/Account/001W000000KY10hIAD"
	},
	Id => "001W000000KY10hIAD",
	Name => "Chase test",
	BillingStreet => undef,
	BillingCity => undef,
	BillingState => undef,
	BillingPostalCode => undef,
	BillingCountry => undef,
	Phone => undef,
};
my $RECORD = {
	attributes => {
		type => "Account",
		url => "/services/data/v34.0/sobjects/Account/001W000000KY10hIAD"
	},
	Id => "001W000000KY10hIAD",
	IsDeleted => 0,
	MasterRecordId => undef,
	Name => "Chase test",
	Type => undef,
	RecordTypeId => "012500000001GNnAAM",
	ParentId => undef,
	BillingStreet => undef,
	BillingCity => undef,
	BillingState => undef,
	BillingPostalCode => undef,
	BillingCountry => undef,
	BillingLatitude => undef,
	BillingLongitude => undef,
	BillingAddress => undef,
	ShippingStreet => undef,
	ShippingCity => undef,
	ShippingState => undef,
	ShippingPostalCode => undef,
	ShippingCountry => undef,
	ShippingLatitude => undef,
	ShippingLongitude => undef,
	ShippingAddress => undef,
	Phone => undef,
	Fax => undef,
	Website => undef,
	PhotoUrl => undef,
	Industry => undef,
	NumberOfEmployees => undef,
	Description => undef,
	OwnerId => "00550000001HWH5AAO",
	CreatedDate => "2015-09-22T01:44:40.000+0000",
	CreatedById => "00550000001HWH5AAO",
	LastModifiedDate => "2015-09-22T01:44:53.000+0000",
	LastModifiedById => "00550000001HWH5AAO",
	SystemModstamp => "2015-09-22T01:44:53.000+0000",
	LastActivityDate => undef,
	LastViewedDate => "2015-09-22T01:44:53.000+0000",
	LastReferencedDate => "2015-09-22T01:44:53.000+0000",
	IsPartner => 0,
	IsCustomerPortal => 0,
	Jigsaw => undef,
	JigsawCompanyId => undef,
	AccountSource => undef,
	SicDesc => undef,
};

my $sf = try { WWW::Salesforce->new(); } catch { BAIL_OUT("Unable to create new instance: $_"); };
isa_ok( $sf, 'WWW::Salesforce', 'Is a proper Salesforce object' ) || BAIL_OUT("can't instantiate");

# setup mock
my $mock = Mojolicious->new;
$mock->log->level('fatal');
$mock->routes->get('/services/data/v33.0/sobjects/:type/:id' => sub {
	my $c = shift;
	return $c->render(status=>401,json=>[{message=>"Session expired or invalid",errorCode=>"INVALID_SESSION_ID"}]) if $ERROR_OUT;
	my $type = $c->stash('type') || '';
	my $id = $c->stash('id') || '';
	my $fields = $c->param('fields') || undef;
	$fields = undef unless $fields && !ref($fields) && $fields eq join(', ', @$FIELDS);
	unless ( $type eq 'Account' ) {
		return $c->render(status=>404,json=>[{errorCode=>"NOT_FOUND",message=>"The requested resource does not exist"}]);
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
	return $c->render(json=>$RECORD_FIELDS) if $fields;
	return $c->render(json=>$RECORD);
});
$sf->ua->server->app($mock); #point the client to the mock

# set the login
$sf->version('33.0');
$sf->login_url(Mojo::URL->new('/'));
$sf->_instance_url('/');
$sf->_access_token('123455663452abacbabababababababanenenenene');
$sf->_access_time(time());
# actual testing
can_ok($sf, qw(retrieve) );

{
	my $error;
	# all the ways a type could fail
	$error = try {return $sf->retrieve() } catch { $_; };
	like( $error, qr/No SObject Type defined/, 'retrieve error: empty call, type errors first');
	$error = try {return $sf->retrieve(undef) } catch { $_; };
	like( $error, qr/No SObject Type defined/, 'retrieve error: undef Type');
	$error = try {return $sf->retrieve('') } catch { $_; };
	like( $error, qr/No SObject Type defined/, 'retrieve error: empty string Type');
	$error = try {return $sf->retrieve({}) } catch { $_; };
	like( $error, qr/No SObject Type defined/, 'retrieve error: hashref Type');
	$error = try {return $sf->retrieve([]) } catch { $_; };
	like( $error, qr/No SObject Type defined/, 'retrieve error: arrayref Type');
	# all the ways an ID could fail
	$error = try {return $sf->retrieve('Type') } catch { $_; };
	like( $error, qr/No SObject ID provided/, 'retrieve error: Type only, ID errors first');
	$error = try {return $sf->retrieve('Type',undef) } catch { $_; };
	like( $error, qr/No SObject ID provided/, 'retrieve error: undef ID');
	$error = try {return $sf->retrieve('Type','') } catch { $_; };
	like( $error, qr/No SObject ID provided/, 'retrieve error: empty string ID');
	$error = try {return $sf->retrieve('Type','1223123123') } catch { $_; };
	like( $error, qr/No SObject ID provided/, 'retrieve error: invalid string ID');
	$error = try {return $sf->retrieve('Type',{}) } catch { $_; };
	like( $error, qr/No SObject ID provided/, 'retrieve error: hashref ID');
	$error = try {return $sf->retrieve('Type',[]) } catch { $_; };
	like( $error, qr/No SObject ID provided/, 'retrieve error: arrayref ID');
	# failures from server
	$error = try {return $sf->retrieve('Type',$ID) } catch { $_; };
	like( $error, qr/NOT_FOUND/, 'retrieve error: not an Account');
	$error = try {return $sf->retrieve('Account',$ID_DEL) } catch { $_; };
	like( $error, qr/DELETED/, 'retrieve error: deleted Account');
	$error = try {return $sf->retrieve('Account',$ID_MAL) } catch { $_; };
	like( $error, qr/MALFORMED_ID/, 'retrieve error: malformed Account');
}

{ #successful blocking
	my $res;
	$res = try {return $sf->retrieve('Account',$ID)} catch {$_};
	is_deeply( $res, $RECORD, 'retrieve: Proper request and response');
	$res = try {return $sf->retrieve('Account',$ID,'')} catch {$_};
	is_deeply( $res, $RECORD, 'retrieve: Proper request and response skipping bad FIELDS');
	$res = try {return $sf->retrieve('Account',$ID,undef)} catch {$_};
	is_deeply( $res, $RECORD, 'retrieve: Proper request and response skipping bad FIELDS undef');
	$res = try {return $sf->retrieve('Account',$ID,{})} catch {$_};
	is_deeply( $res, $RECORD, 'retrieve: Proper request and response skipping bad FIELDS hashref');
	$res = try {return $sf->retrieve('Account',$ID, $FIELDS)} catch {$_};
	is_deeply( $res, $RECORD_FIELDS, 'retrieve: Proper request and response with FIELDS');
}

{ # non-blocking successful
	my ($err, $res);
	Mojo::IOLoop->delay(
		sub { $sf->retrieve('Account', $ID,shift->begin(0))},
		sub { (undef, undef, $err, $res) = @_; }
	)->catch(sub {BAIL_OUT("Something went wrong in retrieve-nb: ".pop)})->wait;
	is($err,undef, 'retrieve-nb: successful - no errors');
	is_deeply($res,$RECORD, "retrieve-nb: correct no sobject type" );

	$err = undef;
	$res = undef;
	Mojo::IOLoop->delay(
		sub { $sf->retrieve('Account', $ID,$FIELDS, shift->begin(0))},
		sub { (undef, undef, $err, $res) = @_; }
	)->catch(sub {BAIL_OUT("Something went wrong in retrieve-nb: ".pop)})->wait;
	is($err,undef, 'retrieve-nb: successful - no errors with FIELDS');
	is_deeply($res,$RECORD_FIELDS, "retrieve-nb: correct no sobject type with FIELDS" );
}

{ # non-blocking Errors
	my ($err, $res);
	Mojo::IOLoop->delay(
		sub { $sf->retrieve('', $ID,shift->begin(0))},
		sub { (undef, undef, $err, $res) = @_; }
	)->catch(sub {BAIL_OUT("Something went wrong in retrieve-nb: ".pop)})->wait;
	like($err,qr/No SObject Type defined/, 'retrieve-nb error: no sobject type');
	is($res,undef, "retrieve-nb: correct no sobject type" );

	$err = undef;
	$res = undef;
	Mojo::IOLoop->delay(
		sub { $sf->retrieve('Type', '',shift->begin(0))},
		sub { (undef, undef, $err, $res) = @_; }
	)->catch(sub {BAIL_OUT("Something went wrong in retrieve-nb: ".pop)})->wait;
	like($err,qr/No SObject ID provided/, 'retrieve-nb error: no sobject id');
	is($res,undef, "retrieve-nb: no sobject id" );

	$ERROR_OUT = 1;
	like( (try{return $sf->retrieve('Account', $ID)} catch {return $_}), qr/401/, "retrieve: error out.");
	$err = undef;
	$res = undef;
	Mojo::IOLoop->delay(
		sub { $sf->retrieve('Account', $ID,shift->begin(0))},
		sub { (undef, undef, $err, $res) = @_; }
	)->catch(sub {BAIL_OUT("Something went wrong in retrieve-nb: ".pop)})->wait;
	like($err,qr/401/, 'retrieve-nb error: correct error');
	is($res,undef, "retrieve-nb: correct no response" );

	$ERROR_OUT=0;
	$sf->_access_token('');
	$err = undef;
	$res = undef;
	Mojo::IOLoop->delay(
		sub { $sf->retrieve('Account', $ID,shift->begin(0))},
		sub { (undef, undef, $err, $res) = @_; }
	)->catch(sub {BAIL_OUT("Something went wrong in retrieve-nb: ".pop)})->wait;
	like($err,qr/404/, 'retrieve-nb error: correct not logged in error');
	is($res,undef, "retrieve-nb: correct not logged in no response" );
}

done_testing;
