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

can_ok($sf, qw(create insert) );

{ # error handling
    my $error = try {
        my $obj = $sf->create('badObject', {empty=>'stuff'});
        return "Unknown result" unless ( $obj && ref($obj) eq 'HASH' );
        return $obj->{id} if ( $obj->{success} && $obj->{id} );
        return join(', ', @{$obj->{errors}}) if ref($obj->{errors}) eq 'ARRAY';
        return "unknown error";
    } catch {
        $_;
    };
    like( $error, qr/bad object/, 'create: got the right error message');
    $error = try { return $sf->create({empty=>'stuff'}); } catch { $_; };
    like( $error, qr/^No SObject Type defined/, 'create: no type error message');
    $error = try { return $sf->create('type',{}); } catch { $_; };
    like( $error, qr/^Empty SObjects are not allowed/, 'create: empty object error message');
    $error = try { return $sf->create('type',{}); } catch { $_; };
    like( $error, qr/^Empty SObjects are not allowed/, 'create: empty object error message');
    $error = try { return $sf->create('type',''); } catch { $_; };
    like( $error, qr/^Empty SObjects are not allowed/, 'create: non-hashref object error message');
    $error = try { return $sf->create('type',undef); } catch { $_; };
    like( $error, qr/^Empty SObjects are not allowed/, 'create: non-hashref object error message');
    $error = try { return $sf->create('type'); } catch { $_; };
    like( $error, qr/^Empty SObjects are not allowed/, 'create: no objects error message');
}

# single object creation tests
my $expected_result = {success=>'true',id=>'01t500000016RuaAAE',errors=>[]};
try {
    #type as top-level hash key
    my $res = $sf->create({type=>'Account',Name=>'test',});
    isa_ok($res, "HASH", "create: got a hashref response");
    is_deeply($res, $expected_result, "create: type_in_object: got a good response");
    #type as attributes hash key
    $res = $sf->create({attributes=>{type=>'Account'},Name=>'test',});
    isa_ok($res, "HASH", "create: got a hashref response");
    is_deeply($res, $expected_result, "create: type_in_object: got a good response");
    #type argument overridden in top-level hash key
    $res = $sf->create('Account',{type=>'ThrowawayType',Name=>'test',});
    isa_ok($res, "HASH", "create: got a hashref response");
    is_deeply($res, $expected_result, "create: type_in_object: got a good response");
    #type argument overridden in attributes hash key
    $res = $sf->create('Account',{attributes=>{type=>'ThrowawayType'},Name=>'test',});
    isa_ok($res, "HASH", "create: got a hashref response");
    is_deeply($res, $expected_result, "create: type_in_object: got a good response");
    #type as first argument and nowhere else
    $res = $sf->create('Account', {Name=>'test',});
    isa_ok($res, "HASH", "create: got a hashref response");
    is_deeply($res, $expected_result, "create: type_before_object: got a good response");
} catch {
	BAIL_OUT("Something went wrong in create: $_");
};
# single object insertion tests
try {
    #type as top-level hash key
    my $res = $sf->insert({type=>'Account',Name=>'test',});
    isa_ok($res, "HASH", "insert: got a hashref response");
    is_deeply($res, $expected_result, "insert: type_in_object: got a good response");
    #type as attributes hash key
    $res = $sf->insert({attributes=>{type=>'Account'},Name=>'test',});
    isa_ok($res, "HASH", "insert: got a hashref response");
    is_deeply($res, $expected_result, "insert: type_in_object: got a good response");
    #type argument overridden in top-level hash key
    $res = $sf->insert('Account',{type=>'ThrowawayType',Name=>'test',});
    isa_ok($res, "HASH", "insert: got a hashref response");
    is_deeply($res, $expected_result, "insert: type_in_object: got a good response");
    #type argument overridden in attributes hash key
    $res = $sf->insert('Account',{attributes=>{type=>'ThrowawayType'},Name=>'test',});
    isa_ok($res, "HASH", "insert: got a hashref response");
    is_deeply($res, $expected_result, "insert: type_in_object: got a good response");
    #type as first argument and nowhere else
    $res = $sf->insert('Account', {Name=>'test',});
    isa_ok($res, "HASH", "insert: got a hashref response");
    is_deeply($res, $expected_result, "insert: type_before_object: got a good response");
} catch {
	BAIL_OUT("Something went wrong in single insert: $_");
};

done_testing;
