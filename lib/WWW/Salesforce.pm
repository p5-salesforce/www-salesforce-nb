package WWW::Salesforce;

use Moo;
use Mojo::URL;
use Mojo::UserAgent;
use strictures 2;
use namespace::clean;
use v5.10;

with 'WWW::Salesforce::Connector';

our $VERSION = '0.009';

# salesforce login attributes
has consumer_key => (is =>'rw',default=>'');
has consumer_secret => (is =>'rw',default=>'');
has login_type => (
	is => 'rw',
	required => 1,
	isa => sub {
		my $val = shift;
		die "Invalid login_type requested." unless $val && grep {$val eq $_} qw(soap oauth2_up);
	},
	default => 'oauth2_up',
);
has login_url => (is => 'rw', required=>1, default => sub {Mojo::URL->new('https://login.salesforce.com/') } );
has max_requests => (is=>'rw',isa =>sub{die "Must be an integer" unless $_[0] =~ /^[0-9]+$/},required => 1,default => '10',);
has password => (is =>'rw',default=>'');
has pass_token => (is =>'rw',default=>'');
has ua => (is => 'ro',required => 1,default => sub {Mojo::UserAgent->new(inactivity_timeout=>50);},);
has username => (is =>'rw',default=>'');
has version => (
	is=>'rw',
	isa =>sub{die "Must be a floating number without the 'v'" unless $_[0] =~ /^[0-9]+\.[0-9]+$/},
	required => 1,
	default => '34.0',
);

sub insert { shift->create(@_) }
sub create {
	my $cb = ($_[-1] && ref($_[-1]) eq 'CODE')? pop: undef;
	my ($self,$type,$object) = @_;
	$object = ($object && ref($object) eq 'HASH')? $object: undef;
	unless ( $object ) {
		if ( $type && ref($type) eq 'HASH' ) {
			$object = $type;
			$type = undef;
		} else {
			$object = {};
		}
	}
	$type = ($type && !ref($type))? $type: undef;
	# The only remaining thing on the call stack should be the hashref SObject
	$type ||= $object->{attributes}{type} || $object->{type} || undef;
	$type = undef unless $type && !ref($type);
	delete($object->{Id});
	delete($object->{type});
	delete($object->{attributes});
	# we have now cleaned up the object and hopefully have a type.
	unless ( $type ) {
		die "No SObject Type defined." unless $cb;
		$self->$cb("No SObject Type defined.", undef);
		return $self;
	}
	unless ( scalar(keys(%$object)) ) {
		die "Empty SObjects are not allowed." unless $cb;
		$self->$cb("Empty SObjects are not allowed.",undef);
		return $self;
	}
	# blocking request
	unless ( $cb ) {
		$self->login();
		my $url = Mojo::URL->new($self->_instance_url)->path($self->_path)->path("sobjects/$type");
		my $tx = $self->ua->post($url, $self->_headers(), json => $object);
		die $self->_error($tx->error, $tx->res->json) unless $tx->success;
		return $tx->res->json;
	}

	# non-blocking request
	$self->login(sub {
		my ( $sf, $err, $token ) = @_;
		return $sf->$cb($err,undef) if $err;
		my $url = Mojo::URL->new($sf->_instance_url)->path($sf->_path)->path("sobjects/$type");
		$sf->ua->post($url, $sf->_headers(), json=>$object,sub {
			my ($ua, $tx) = @_;
			return $sf->$cb($sf->_error($tx->error, $tx->res->json),undef) unless $tx->success;
			return $sf->$cb(undef,$tx->res->json);
		});
	});
	return $self;
}

sub destroy { shift->delete(@_) }
sub del { shift->delete(@_) }
sub delete {
	my $cb = ($_[-1] && ref($_[-1]) eq 'CODE')? pop: undef;
	my ($self, $type, $id) = @_;
	$type = undef unless ( $type && !ref($type) );
	$id = undef unless ( $id && !ref($id) && $id =~ /^[a-zA-Z0-9]{15,18}$/ );

	unless ( $type ) {
		die "No SObject Type defined." unless $cb;
		$self->$cb("No SObject Type defined.", undef);
		return $self;
	}
	unless ( $id ) {
		die "No SObject ID provided." unless $cb;
		$self->$cb("No SObject ID provided.", undef);
		return $self;
	}

	# blocking request
	unless ( $cb ) {
		$self->login();
		my $url = Mojo::URL->new($self->_instance_url)->path($self->_path)->path("sobjects/$type/$id");
		my $tx = $self->ua->delete($url, $self->_headers());
		die $self->_error($tx->error, $tx->res->json) unless $tx->success;
		# on success, just return the following
		return {id=>$id,success=>1,errors=>[]};
	}

	# non-blocking request
	$self->login(sub {
		my ( $sf, $err, $token ) = @_;
		return $sf->$cb($err,) if $err;
		my $url = Mojo::URL->new($sf->_instance_url)->path($sf->_path)->path("sobjects/$type/$id");
		$sf->ua->delete($url, $sf->_headers(), sub {
			my ($ua, $tx) = @_;
			return $sf->$cb($sf->_error($tx->error, $tx->res->json),undef) unless $tx->success;
			return $sf->$cb(undef,{id=>$id,success=>1,errors=>[]});
		});
	});
}

# describe an object
sub describe_sobject { shift->describe(@_) }
sub describe {
	my $cb = ($_[-1] && ref($_[-1]) eq 'CODE')? pop: undef;
	my ($self,$object) = @_;
	$object = ($object && !ref($object))?$object:undef;
	unless ($object) {
		die 'An object is required to describe it' unless $cb;
		$self->$cb('An object is required to describe it',undef);
		return $self;
	}

	# blocking request
	unless ( $cb ) {
		$self->login(); # handles renewing the auth token if necessary
		my $url = Mojo::URL->new($self->_instance_url)->path($self->_path)->path("sobjects/$object/describe");
		my $tx = $self->ua->get($url, $self->_headers());
		die $self->_error($tx->error, $tx->res->json) unless $tx->success;
		return $tx->res->json;
	}

	# non-blocking request
	$self->login(sub {
		my ( $sf, $err, $token ) = @_;
		return $sf->$cb($err,undef) if $err;
		my $url = Mojo::URL->new($sf->_instance_url)->path($sf->_path)->path("sobjects/$object/describe");
		$sf->ua->get($url, $sf->_headers(), sub {
			my ($ua, $tx) = @_;
			return $sf->$cb($sf->_error($tx->error, $tx->res->json),undef) unless $tx->success;
			return $sf->$cb(undef,$tx->res->json);
		});
	});
	return $self;
}

sub describe_global {
	my ($self, $cb) = @_;
	$cb = ($cb && ref($cb) eq 'CODE')? $cb: undef;

	# blocking request
	unless ( $cb ) {
		$self->login(); # handles renewing the auth token if necessary
		my $url = Mojo::URL->new($self->_instance_url)->path($self->_path)->path("sobjects");
		my $tx = $self->ua->get($url, $self->_headers());
		# uncoverable branch true
		die $self->_error($tx->error, $tx->res->json) unless $tx->success;
		return $tx->res->json;
	}

	# non-blocking request
	$self->login(sub {
		my ( $sf, $err, $token ) = @_;
		return $sf->$cb($err,undef) if $err;
		my $url = Mojo::URL->new($sf->_instance_url)->path($sf->_path)->path("sobjects");
		$sf->ua->get($url, $sf->_headers(), sub {
			my ($ua, $tx) = @_;
			# uncoverable branch true
			return $sf->$cb($sf->_error($tx->error, $tx->res->json),undef) unless $tx->success;
			return $sf->$cb(undef,$tx->res->json);
		});
	});
	return $self;
}

# get our limits
sub limits {
	my ($self, $cb) = @_;
	$cb = ($cb && ref($cb) eq 'CODE')? $cb: undef;
	# blocking request
	unless ( $cb ) {
		$self->login(); # handles renewing the auth token if necessary
		my $url = Mojo::URL->new($self->_instance_url)->path($self->_path)->path("limits");
		my $tx = $self->ua->get($url, $self->_headers());
		die $self->_error($tx->error, $tx->res->json) unless $tx->success;
		return $tx->res->json;
	}

	# non-blocking request
	$self->login(sub {
		my ( $sf, $err, $token ) = @_;
		return $sf->$cb($err,[]) if $err;
		return $sf->$cb('No login token',[]) unless $token;
		my $url = Mojo::URL->new($sf->_instance_url)->path($sf->_path)->path("limits");
		$sf->ua->get($url, $sf->_headers(), sub {
			my ($ua, $tx) = @_;
			return $sf->$cb($sf->_error($tx->error, $tx->res->json),undef) unless $tx->success;
			return $sf->$cb(undef,$tx->res->json);
		});
	});
	return $self;
}

# run a query
sub query {
	my ($self, $query, $cb) = @_;
	$cb = ($cb && ref($cb) eq 'CODE')? $cb: undef;
	unless ($query) {
		die 'A query is required' unless $cb;
		$self->$cb('A query is required',[]);
		return $self;
	}

	# blocking request
	unless ( $cb ) {
		$self->login(); # handles renewing the auth token if necessary
		my $results = [];
		my $url = Mojo::URL->new($self->_instance_url)->path($self->_path)->path('query/');
		my $tx = $self->ua->get( $url, $self->_headers(), form => { q => $query, } );
		while(1) {
			die $self->_error($tx->error, $tx->res->json) unless $tx->success;
			my $json = $tx->res->json;
			last unless $json && $json->{records};
			push @{$results}, @{$json->{records}};

			last if $json->{done};
			last unless $json->{nextRecordsUrl};
			$url = Mojo::URL->new($self->_instance_url)->path($json->{nextRecordsUrl});
			$tx = $self->ua->get( $url, $self->_headers() );
		}
		return $results;
	}

	# non-blocking request
	$self->login(sub {
		my ( $sf, $err, $token ) = @_;
		return $sf->$cb($err,[]) if $err;
		return $sf->$cb('No login token',[]) unless $token;
		my $url = Mojo::URL->new($sf->_instance_url)->path($sf->_path)->path('query/');
		my $results = [];
		my $results_nb;
		$results_nb = sub {
			my ($ua,$tx) = @_;
			return $sf->$cb($sf->_error($tx->error, $tx->res->json),$results) unless $tx->success;
			my $data = $tx->res->json;
			push @{$results}, @{$data->{records}};
			return $sf->$cb(undef,$results) if $data->{done};
			return $sf->$cb(undef,$results) unless $data->{nextRecordsUrl};
			$sf->ua->get(Mojo::URL->new($sf->_instance_url)->path($data->{nextRecordsUrl}), $sf->_headers(), $results_nb);
		};
		$sf->ua->get($url, $sf->_headers(), form => { q => $query, }, $results_nb);
	});
	return $self;
}

# grab a single object
sub retrieve {
	my $cb = ($_[-1] && ref($_[-1]) eq 'CODE')? pop: undef;
	my ( $self, $object, $id, $fields ) = @_;
	$fields = ($fields && ref($fields) eq 'ARRAY')? $fields: undef;
	unless ($object) {
		die( "An SObject type is required for retrieve()" ) unless $cb;
		$self->$cb('An SObject type is required for retrieve()',[]) if $cb;
		return $self;
	}
	unless ($id && $id =~ /^[a-zA-Z0-9]+$/) {
		die( "An SObject ID is required for retrieve()" ) unless $cb;
		$self->$cb('An SObject ID is required for retrieve()',[]) if $cb;
		return $self;
	}
	#blocking request
	unless ($cb) {
		$self->login();
		my $url = Mojo::URL->new($self->_instance_url)->path($self->_path)->path("sobjects/$object/$id");
		$url->query('fields'=> join(', ', @{$fields})) if $fields;
		my $tx = $self->ua->get( $url, $self->_headers() );
		die $self->_error($tx->error, $tx->res->json) unless $tx->success;
		return $tx->res->json;
	}

	# non-blocking request
	$self->login(sub {
		my ( $sf, $err, $token ) = @_;
		return $sf->$cb($err,[]) if $err;
		return $sf->$cb('No login token',[]) unless $token;
		my $url = Mojo::URL->new($sf->_instance_url)->path($sf->_path)->path("sobjects/$object/$id");
		$url->query('fields'=> join(', ', @{$fields})) if $fields;
		$sf->ua->get($url, $sf->_headers(), sub {
			my ($ua, $tx) = @_;
			return $sf->$cb($sf->_error($tx->error, $tx->res->json),undef) unless $tx->success;
			return $sf->$cb(undef,$tx->res->json);
		});
	});
	return $self;
}

# describe an object
sub search {
	my ($self, $sosl, $cb) = @_;
	$cb = ($cb && ref($cb) eq 'CODE')? $cb: undef;
	unless ($sosl) {
		die 'An SOSL statement is required to search' unless $cb;
		$self->$cb('An SOSL statement is required to search',undef);
		return $self;
	}

	# blocking request
	unless ( $cb ) {
		$self->login(); # handles renewing the auth token if necessary
		my $url = Mojo::URL->new($self->_instance_url)->path($self->_path)->path("search/");
		$url->query(q=>$sosl);
		my $tx = $self->ua->get($url, $self->_headers());
		die $self->_error($tx->error, $tx->res->json) unless $tx->success;
		return $tx->res->json;
	}

	# non-blocking request
	$self->login(sub {
		my ( $sf, $err, $token ) = @_;
		return $sf->$cb($err,[]) if $err;
		return $sf->$cb('No login token',[]) unless $token;
		my $url = Mojo::URL->new($sf->_instance_url)->path($sf->_path)->path("search/");
		$url->query(q=>$sosl);
		$sf->ua->get($url, $sf->_headers(), sub {
			my ($ua, $tx) = @_;
			return $sf->$cb($sf->_error($tx->error, $tx->res->json),undef) unless $tx->success;
			return $sf->$cb(undef,$tx->res->json);
		});
	});
	return $self;
}

sub update {
	my ($self,$type,$id,$object,$cb) = @_;
	$cb = ($cb && ref($cb) eq 'CODE')? $cb: undef;
	$id = ($id && !ref($id) && $id =~ /^[a-zA-Z0-9]{15,18}$/)?$id: undef;
	$object = ($object && ref($object) eq 'HASH')? $object: {};

	$type = ($type && !ref($type))? $type : $object->{attributes}{type} || $object->{type} || undef;
	$type = undef unless $type && !ref($type);

	delete($object->{Id});
	delete($object->{type});
	delete($object->{attributes});

	# we have now cleaned up the object and hopefully have a type and Id.
	unless ( $type ) {
		die "No SObject Type defined." unless $cb;
		$self->$cb("No SObject Type defined.", undef);
		return $self;
	}
	unless ( $id ) {
		die "No SObject ID provided." unless $cb;
		$self->$cb("No SObject ID provided.", undef);
		return $self;
	}
	unless ( scalar(keys(%$object)) ) {
		die "Empty SObjects are not allowed." unless $cb;
		$self->$cb("Empty SObjects are not allowed.",undef);
		return $self;
	}

	# blocking request
	unless ( $cb ) {
		$self->login();
		my $url = Mojo::URL->new($self->_instance_url)->path($self->_path)->path("sobjects/$type/$id");
		my $tx = $self->ua->patch($url, $self->_headers(), json => $object);
		die $self->_error($tx->error, $tx->res->json) unless $tx->success;
		return $tx->res->json || {id=>$id,success=>1,errors=>[],};
	}

	# non-blocking request
	$self->login(sub {
		my ( $sf, $err, $token ) = @_;
		return $sf->$cb($err,[]) if $err;
		return $sf->$cb('No login token',[]) unless $token;
		my $url = Mojo::URL->new($sf->_instance_url)->path($sf->_path)->path("sobjects/$type/$id");
		$sf->ua->patch($url, $sf->_headers(), json=>$object,sub {
			my ($ua, $tx) = @_;
			return $sf->$cb($sf->_error($tx->error, $tx->res->json),undef) unless $tx->success;
			return $sf->$cb(undef,($tx->res->json || {id=>$id,success=>1,errors=>[],}));
		});
	});
	return $self;

}

# create an error string
sub _error {
	my ( $self, $error, $data ) = @_;
	my $message = '';
	if ( $error && ref($error) eq 'HASH' ) {
		$message = $error->{code}||500;
		my $emsg = $error->{message}||'';
		$message .= " $emsg" if $emsg;
	}
	return $message unless $data;

	if ( ref($data) eq 'HASH' ) {
		my $ecode = $data->{errorCode}||$data->{error}||'';
		my $emsg = $data->{message}||$data->{error_description}||'';
		$message .= ", $ecode: $emsg" if $ecode || $emsg;
		return $message;
	}
	return $message unless ref($data) eq 'ARRAY';
	for my $err ( @{$data} ) {
		next unless $err && ref($err) eq 'HASH';
		my $ecode = $err->{errorCode}||$err->{error}||'';
		my $emsg = $err->{message}||$err->{error_description}||'';
		$message .= ", $ecode: $emsg" if $ecode || $emsg;
	}
	return $message;
}

# Get the headers we need to send each time
sub _headers {
	my ($self, $type) = @_;
	my $header = {
		Accept => 'application/json',
		DNT => 1,
		'Sforce-Query-Options' => 'batchSize=2000',
		'Accept-Charset' => 'UTF-8',
	};
	if ( $type && $type eq 'soap' ) {
		$header->{Accept} = 'text/xml';
		$header->{'Content-Type'} = 'text/xml; charset=utf-8';
		$header->{SOAPAction} = '""';
		$header->{Expect} = '100-continue';
		my $url = Mojo::URL->new($self->_instance_url || $self->login_url || '');
		$header->{Host} = $url->host if $url->host;
	}
	if ( my $token = $self->_access_token ) {
		$header->{'Authorization'} = "Bearer $token";
	}
	return $header;
}

sub _path {
	my ($self, $type) = @_;
	if ( $type && $type eq 'soap' ) {
		return '/services/Soap/u/'.$self->version.'/';
	}
	return '/services/data/v'.$self->version.'/';
}

1;


=encoding utf8

=head1 NAME

WWW::Salesforce - Perl communication with the Salesforce RESTful API

=head1 SYNOPSIS

	#!/usr/bin/env perl
	use Mojo::Base -strict;
	use WWW::Salesforce;
	use Try::Tiny qw(try catch);

	# via soap
	my $sf_soap = WWW::Salesforce->new(
		login_type => 'soap',
		login_url => Mojo::URL->new('https://login.salesforce.com'),
		version => '34.0',
		username => 'foo@bar.com',
		password => 'mypassword',
		pass_token => 'mypasswordtoken123214123521345',
	);
	# via OAuth2 username and password
	my $sf_oauth2 = WWW::Salesforce->new(
		login_type => 'oauth2_up', # this is the default
		login_url => Mojo::URL->new('https://login.salesforce.com'),
		version => '34.0',
		consumer_key => 'alksdlkj3hasdg;jlaksghajdhgaghasdg.asdgfasodihgaopih.asdf',
		consumer_secret => 'asdfasdjkfh234123513245',
		username => 'foo@bar.com',
		password => 'mypassword',
		pass_token => 'mypasswordtoken123214123521345',
	);

	# blocking method
	# calling login() will happen automatically.
	try {
		my $res_soap = $sf_soap->query('Select Id, Name, Phone from Account');
		say "found ", scalar(@{$res_soap}), " results via SOAP then RESTful API.";
		my $res_oauth = $sf_oauth2->query('Select Id, Name, Phone from Account');
		say "found ", scalar(@{$res_oauth}), " results via OAuth2 then RESTful API.";
	}
	catch {
		die "Couldn't query the service: $_";
	};

	# non-blocking method
	# calling login() will happen automatically
	Mojo::IOLoop->delay(
		sub {
			my $delay = shift;
			$sf_soap->query('select Id from Account', $delay->begin);
			$sf_oauth2->query('select Id from Account', $delay->begin);
		},
		sub {
			my ($delay, $err,$soap,$err2,$oauth) = @_;
			Carp::croak( $err ) if $err; # make it fatal
			Carp::croak( $err2 ) if $err2; # make it fatal
			say scalar(@$soap), " from soap";
			say scalar(@$oauth), " from oauth2";
		},
	)->catch(sub {say "uh oh, ",pop;})->wait;

=head1 DESCRIPTION

L<WWW::Salesforce> allows us to connect to L<Salesforce|http://www.salesforce.com/>'s service to access our data using their L<RESTful API|https://developer.salesforce.com/docs/atlas.en-us.api_rest.meta/api_rest/>.

Creation of a new L<WWW::Salesforce> instance will not actually hit the server.  The first communication with the L<Salesforce|http://www.salesforce.com/> API occurs when you specifically call the C<login> method or when you make another call.

All API calls using this library will first make sure you are properly logged in.

=over

=item oauth2_up

This is the default: OAuth2 using the username and password (up) method: L<Session ID Authorization|https://developer.salesforce.com/docs/atlas.en-us.api_rest.meta/api_rest/quickstart_oauth.htm> L<Salesforce Username-Password OAuth Authentication Flow|https://developer.salesforce.com/docs/atlas.en-us.api_rest.meta/api_rest/intro_understanding_username_password_oauth_flow.htm>

=item soap

Alternately, you can use the soap login method: L<Salesforce SOAP-based username and password login flow|https://developer.salesforce.com/docs/atlas.en-us.api.meta/api/sforce_api_calls_login.htm>

=back

=head1 ATTRIBUTES

L<WWW::Salesforce> makes the following attributes available.

=head2 consumer_key

	my $key = $sf->consumer_key;
	$key = $sf->consumer_key( 'alksdlkj3hh.asdf' );

The Consumer Key (also referred to as the client_id in the Saleforce documentation) is part of your L<Connected App|http://www.salesforce.com/us/developer/docs/api_rest/Content/intro_defining_remote_access_applications.htm>.  It is a required field to be able to login.

Note, this attribute is only used to generate the access token during C<login>. You may want to C<logout> before changing this setting.

=head2 consumer_secret

	my $secret = $sf->consumer_secret;
	$secret = $sf->consumer_secret( 'asdfasdjkfh234123513245' );

The Consumer Secret (also referred to as the client_secret in the Saleforce documentation) is part of your L<Connected App|http://www.salesforce.com/us/developer/docs/api_rest/Content/intro_defining_remote_access_applications.htm>.  It is a required field to be able to login.

Note, this attribute is only used to generate the access token during C<login>. You may want to C<logout> before changing this setting.

=head2 login_type

	my $type = $sf->login_type;
	$type = $sf->login_type( 'oauth2_up' );

This is what will determine our login method of choice. No matter which login
method you choose, we're going to communicate to the Salesforce services using an
C<Authorization: Bearer token> header. The login method just dictates how we
will request that token from Salesforce.
Different methods of login require slightly different sets of data in order for the login to take place.

You may want to C<logout> before changing this setting.

Available types are:

=over

=item oauth2_up

This login type is the default.  It will require your C<consumer_key>, C<consumer_secret>, C<username>, C<password>, C<pass_token> and C<login_url>.  This method will go through the L<Salesforce Username-Password OAuth Authentication Flow|http://www.salesforce.com/us/developer/docs/api_rest/Content/intro_understanding_username_password_oauth_flow.htm>.

=item soap

This method will only require your C<username>, C<password>, C<pass_token> and C<login_url>.
It will go through the L<Salesforce SOAP-based username and password login flow|https://developer.salesforce.com/docs/atlas.en-us.api.meta/api/sforce_api_calls_login.htm>.

=back

=head2 login_url

	my $host = $sf->login_url;
	$host = $sf->login_url( Mojo::URL->new('https://test.salesforce.com') );

This is the base host of the API we're using.  This allows you to use any of your sandbox or live data areas easily. You may want to C<logout> before changing this setting.

=head2 pass_token

	my $token = $sf->pass_token;
	$token = $sf->pass_token( 'mypasswordtoken123214123521345' );

The password token is a Salesforce-generated token to go along with your password.  It is appended to the end of your password and used only during C<login> authentication.

Note, this attribute is only used to generate the access token during C<login>. You may want to C<logout> before changing this setting.

=head2 password

	my $password = $sf->password;
	$password = $sf->password( 'mypassword' );

The password is the password you set for your user account in Salesforce.

Note, this attribute is only used to generate the access token during C<login>. You may want to C<logout> before changing this setting.

=head2 ua

	my $ua = $sf->ua;

The L<Mojo::UserAgent> is the user agent we use to communicate with the Salesforce services.  For C<proxy> and other needs, see the L<Mojo::UserAgent> documentation.

=head2 username

	my $username = $sf->username;
	$username = $sf->username( 'foo@bar.com' );

The username is the email address you set for your user account in Salesforce.

Note, this attribute is only used to generate the access token during C<login>. You may want to C<logout> before changing this setting.

=head2 version

	my $version = $sf->version;
	$version = $sf->version( '34.0' );

Tell us what API version you'd like to use.  Leave off the C<v> from the version number.

=head1 METHODS

L<WWW::Salesforce> makes the following methods available.

=head2 insert

Synonym for C<create>

=head2 create

	# blocking
	try {
		my $res = $sf->create('Account',{fieldName=>'value'});
		if ( $res->{success} ) { # even if the tx succeeds, check the response!
			say "Newly entered Account goes by the id: ",$res->{id};
		}
		else {
			die Dumper $res->{errors};
		}
	} catch {
		die "Errors: $_";
	};

	# non-blocking
	$sf->create('Account',{fieldName=>'value'}, sub {
		my ($sf, $err, $res) = @_;
		die "Got an error trying to create the Account: $err" if $err;
		if ( $res->{success} ) { # even if the tx succeeds, check the response!
			say "Newly entered Account goes by the id: ",$res->{id};
		}
		else {
			die Dumper $res->{errors};
		}
	});

This method calls the Salesforce L<Create method|https://developer.salesforce.com/docs/atlas.en-us.api_rest.meta/api_rest/dome_sobject_create.htm>.
On a successful transaction, a JSON response is returned with three fields (C<id>, C<success>, and C<errors>).  You should check that response to see if your creation attempt actually succeeded.

=head2 del

Synonym for C<delete>.

=head2 destroy

Synonym for C<delete>.

=head2 delete

	# blocking
	try {
		my $res = $sf->delete('Account',$id);
		if ( $res->{success} ) { # even if the tx succeeds, check the response!
			say "Deleted the id: ",$res->{id};
		}
		else {
			die Dumper $res->{errors};
		}
	} catch {
		die "Errors: $_";
	};

	# non-blocking
	$sf->delete('Account',$id, sub {
		my ($sf, $err, $res) = @_;
		die "Got an error trying to delete the Account: $err" if $err;
		if ( $res->{success} ) { # even if the tx succeeds, check the response!
			say "Deleted the id: ",$res->{id};
		}
		else {
			die Dumper $res->{errors};
		}
	});

This method calls the Salesforce L<Delete method|https://developer.salesforce.com/docs/atlas.en-us.api_rest.meta/api_rest/dome_delete_record.htm>.
On a successful transaction, a JSON response is returned with three fields (C<id>, C<success>, and C<errors>).  You should check that response to see if your creation attempt actually succeeded.

=head2 describe_sobject

Synonym for C<describe>

=head2 describe

# blocking
try {
	my $res = $sf->describe('Account');
	say Dumper $res; #all the info about the Account SObject
} catch {
	die "Errors: $_";
};

# non-blocking
$sf->describe('Account', sub {
	my ($sf, $err, $res) = @_;
	die "Got an error trying to describe the Account: $err" if $err;
	say Dumper $res; #all the info about the Account SObject
});

This method calls the Salesforce L<Describe method|https://developer.salesforce.com/docs/atlas.en-us.api_rest.meta/api_rest/resources_sobject_describe.htm>.
On a successful transaction, a JSON response is returned with data full of useful information about the SObject.

=head2 describe_global

# blocking
try {
	my $res = $sf->describe_global();
	say Dumper $res; #all the info
} catch {
	die "Errors: $_";
};

# non-blocking
$sf->describe_global(sub {
	my ($sf, $err, $res) = @_;
	die "Got an error trying to describe_global: $err" if $err;
	say Dumper $res; #all the info
});

This method calls the Salesforce L<Describe Global method|https://developer.salesforce.com/docs/atlas.en-us.api_rest.meta/api_rest/resources_describeGlobal.htm>.
On a successful transaction, a JSON response is returned with data full of useful information about the available objects and their metadata for your organization’s data.

=head2 limits

# blocking
try {
	my $results = $sf->limits();
	say Dumper $results;
} catch {
	die "Errors: $_";
};

# non-blocking
$sf->limits(sub {
	my ($sf, $err, $results) = @_;
	say Dumper $results;
});

This method calls the Salesforce L<Limits method|https://developer.salesforce.com/docs/atlas.en-us.api_rest.meta/api_rest/resources_limits.htm>.

=head2 login

	# blocking
	try {
		$sf = $sf->login(); # allows for method-chaining
	} catch {
		die "Errors: $_";
	};

	# non-blocking
	$sf->login(sub {
		my ($sf, $err, $token) = @_;
		say "Our auth token is: $token";
	});

This method will and go through the L<Salesforce Username-Password OAuth Authentication Flow|http://www.salesforce.com/us/developer/docs/api_rest/Content/intro_understanding_username_password_oauth_flow.htm>
process if it needs to.
Calling this method on your own is not necessary as any API call will call C<login> if necessary.  This could be helpful if you're changing C<api_host>s on your instance.
This method will update your C<access_token> on a successful login.

=head2 logout

	# blocking
	try {
		$sf = $sf->logout(); # allows for method chaining.
	} catch {
		die "Errors: $_";
	};

	# non-blocking
	$sf->logout(sub {
		my ( $sf, $err ) = @_;
		say "We're logged out" unless $err;
	});

This method will go through the L<Token Revocation Process|https://developer.salesforce.com/docs/atlas.en-us.api_rest.meta/api_rest/intro_understanding_oauth_endpoints.htm>.
It also removes knowledge of your access token so that you can login again on your next API call.

=head2 query

	# blocking
	try {
		my $results = $sf->query('Select Id, Name, Phone from Account');
		say Dumper $results;
	} catch {
		die "Errors: $_";
	};

	# non-blocking
	$sf->query('select Id, Name, Phone from Account', sub {
		my ($sf, $err, $results) = @_;
		say Dumper $results;
	});

This method calls the Salesforce L<Query method|http://www.salesforce.com/us/developer/docs/api_rest/Content/resources_query.htm>.  It will keep grabbing and adding the records to your resultant array reference until there are no more records available to your query.
Your query string must be in the form of an L<SOQL String|https://developer.salesforce.com/docs/atlas.en-us.soql_sosl.meta/soql_sosl/sforce_api_calls_soql_select.htm>.

=head2 retrieve

# blocking
try {
	my $results = $sf->retrieve('Account','01231ABCDFQ2100002', [qw(Optional FieldName List Here)]);
	say Dumper $results;
} catch {
	die "Errors: $_";
};

# non-blocking
$sf->retrieve('Account','01231ABCDFQ2100002', [qw(Optional FieldName List Here)], sub {
	my ($sf, $err, $results) = @_;
	say Dumper $results;
});

This method calls the Salesforce L<Retrieve method|https://developer.salesforce.com/docs/atlas.en-us.api_rest.meta/api_rest/dome_get_field_values.htm>.

=head2 search

# blocking
try {
	my $results = $sf->search('FIND{genio*}');
	say Dumper $results;
} catch {
	die "Errors: $_";
};

# non-blocking
$sf->search('FIND{genio*}', sub {
	my ($sf, $err, $results) = @_;
	say Dumper $results;
});

This method calls the Salesforce L<Search method|https://developer.salesforce.com/docs/atlas.en-us.api_rest.meta/api_rest/resources_search.htm>.
Your search query must be in the form of an L<SOSL String|https://developer.salesforce.com/docs/atlas.en-us.soql_sosl.meta/soql_sosl/sforce_api_calls_sosl_syntax.htm>.

=head2 update

	# blocking
	try {
		my $results = $sf->update('SObject_Type','SObject_Id', {Name=>'New Name',});
		say Dumper $results;
	} catch {
		die "Errors: $_";
	};

	# non-blocking
	$sf->query('SObject_Type','SObject_Id', {Name=>'New Name',}, sub {
		my ($sf, $err, $results) = @_;
		say Dumper $results;
	});

This method calls the Salesforce L<Update method|https://developer.salesforce.com/docs/atlas.en-us.api_rest.meta/api_rest/dome_update_fields.htm>.

=head1 ERROR HANDLING

All blocking method calls will C<die> on error and thus you should use L<Try::Tiny> a lot.

	# blocking call
	use Try::Tiny qw(try catch);
	try {
		my $res = $sf->do_something();
	} catch {
		die "uh oh: $_";
	};

All non-blocking methods will return an error string to the callback if there is one:

	# non-blocking call
	$sf->do_something(sub {
		my ( $instance, $error_string, $results ) = @_;
		die "uh oh: $error_string" if $error_string;
	});

=head1 AUTHOR

Chase Whitener << <cwhitener at gmail.com> >>

=head1 BUGS

Please report any bugs or feature requests on GitHub L<https://github.com/genio/www-salesforce-nb/issues>.
I appreciate any and all criticism, bug reports, enhancements, or fixes.

=head1 SUPPORT

You can find documentation for this module with the perldoc command.

		perldoc WWW::Salesforce

You can also look for information at:

=over 4

=item * GitHub

L<https://github.com/genio/www-salesforce-nb>

=back

=head1 ACKNOWLEDGEMENTS

=head1 LICENSE AND COPYRIGHT

Copyright 2015

This program is free software, you can redistribute it and/or modify it under
the terms of the Artistic License version 2.0.

=head1 SEE ALSO

L<https://github.com/kraih/mojo>, L<Mojolicious::Guides>,
L<http://mojolicio.us>.

=cut
