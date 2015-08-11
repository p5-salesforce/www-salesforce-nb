package WWW::Salesforce;

use Moo;
use Mojo::Date;
use Mojo::IOLoop;
use Mojo::URL;
use Mojo::UserAgent;
use strictures 2;
use namespace::clean;

our $VERSION = '0.004';

has '_api_path' => (is=>'rw',default=>'');
has '_access_token' => (is=>'rw',default=>'');
has '_access_time' => (is=>'rw',default=>'0');
# salesforce login attributes
has api_host => (is => 'rw', required=>1, default => sub {Mojo::URL->new('https://login.salesforce.com/') } );
has consumer_key => (is =>'rw',default=>'');
has consumer_secret => (is =>'rw',default=>'');
has username => (is =>'rw',default=>'');
has password => (is =>'rw',default=>'');
has pass_token => (is =>'rw',default=>'');
has 'ua' => (
	is => 'ro',
	required => 1,
	default => sub {Mojo::UserAgent->new(inactivity_timeout=>50);},
	handles => [qw(emit catch on)],
);


# If we already know the latest API path, then use it, otherwise ask Salesforce
# for a list and parse that list to obtain the latest.
sub api_path {
	my ($self, $cb) = @_;
	$cb = ($cb && ref($cb) eq 'CODE')? $cb: undef;
	if ( my $path = $self->_api_path ) {
		return $cb? $self->$cb($path): $path;
	}
	unless ($cb) {
		my $tx = $self->ua->get( Mojo::URL->new($self->api_host)->path("/services/data"), $self->_headers() );
		return $self->_error($tx->error, $tx->res->json) unless $tx->success;
		return $self->_api_latest($tx->success->json);
	}
	return Mojo::IOLoop->delay(
		sub {
			$self->ua->get( Mojo::URL->new($self->api_host)->path("/services/data"), $self->_headers(), shift->begin(0) );
		},
		sub {
			my ($delay, $ua, $tx) = @_;
			return $self->_error($tx->error, $tx->res->json) unless $tx->success;
			my $path = $self->_api_latest($tx->res->json);
			$self->_api_path($path) if $path;
			return $self->$cb($path);
		}
	)->catch(sub {
		my ( $delay, $err ) = @_;
		$self->emit(error=>$err);
	})->wait();
}

# attempt a login to Salesforce to obtain a token
sub login {
	my ($self, $cb) = @_;
	$cb = ($cb && ref($cb) eq 'CODE')? $cb: undef;
	unless ( $self->_login_required ) {
		return $cb? $self->$cb($self->_access_token): $self;
	}

	my $url = Mojo::URL->new($self->api_host)->path("/services/oauth2/token");
	my $form = {
		grant_type => 'password',
		client_id => $self->consumer_key,
		client_secret => $self->consumer_secret,
		username => $self->username,
		password => $self->password . $self->pass_token,
	};

	# blocking request
	unless ($cb) {
		my $tx = $self->ua->post($url, $self->_headers(), form => $form);
		return $self->_error($tx->error, $tx->res->json) unless $tx->success;
		my $data = $tx->res->json;
		$self->api_host($data->{instance_url});
		$self->_access_token($data->{access_token});
		$self->_access_time($data->{issued_at}/1000); #convert milliseconds to seconds
		$self->api_path(); # get the latest API path available to us
		return $self;
	}

	# non-blocking request
	return Mojo::IOLoop->delay(
		sub { $self->ua->post($url, $self->_headers(), form => $form, shift->begin(0)); },
		sub {
			my ($delay, $ua, $tx) = @_;
			return $self->_error($tx->error, $tx->res->json) unless $tx->success;
			my $data = $tx->res->json;
			$self->api_host(Mojo::URL->new($data->{instance_url}));
			$self->_access_token($data->{access_token});
			$self->_access_time($data->{issued_at}/1000); #convert milliseconds to seconds
			$self->api_path( $delay->begin() );
		},
		sub {
			my ( $delay, $path ) = @_;
			return $self->$cb(undef) unless $path;
			return $self->$cb($self->_access_token);
		}
	)->catch(sub {
		my ( $delay, $err ) = @_;
		$self->emit(error=>$err);
	})->wait();
}

sub logout {
	my $self = shift;
	$self->_api_path(undef);
	$self->_access_token(undef);
	$self->_access_time(0);
	return $self;
}

sub query {
	my ($self, $query, $cb) = @_;
	$cb = ($cb && ref($cb) eq 'CODE')? $cb: undef;

	# blocking request
	unless ( $cb ) {
		return [] unless $query;
		$self->login(); # handles renewing the auth token if necessary
		my $results = [];
		my $url = Mojo::URL->new($self->api_host)->path($self->api_path)->path('query/');
		my $tx = $self->ua->get( $url, $self->_headers(), form => { q => $query, } );
		while(1) {
			return $self->_error($tx->error, $tx->res->json) unless $tx->success;
			my $json = $tx->res->json;
			last unless $json && $json->{records};
			push @{$results}, @{$json->{records}};

			last if $json->{done};
			last unless $json->{nextRecordsUrl};
			$self->login();
			$url = Mojo::URL->new($self->api_host)->path($json->{nextRecordsUrl});
			$tx = $self->ua->get( $url, $self->_headers() );
		}
		return $results;
	}
	# non-blocking request
	return $self->$cb([]) unless $query;
	return Mojo::IOLoop->delay(
		sub {
			my $delay = shift;
			$self->login($delay->begin(0));
		},
		sub {
			my ( $delay, $sf, $token ) = @_;
			return $self->$cb([]) unless $token;
			my $url = Mojo::URL->new($self->api_host)->path($self->_api_path)->path('query/');
			$delay->data(self=>$self,cb=>$cb);
			$delay->steps(\&_query_results_nb);
			$self->ua->get($url, $self->_headers(), form => {q=>$query,}, $delay->begin(0) );
		}
	)->catch(sub {
		my ( $delay, $err ) = @_;
		$self->emit(error=>$err);
	})->wait();
}

# parse through the API path results to select the latest available API version.
sub _api_latest {
	my ($self,$data) = @_;
	return undef unless $data && ref($data) && ref($data) eq 'ARRAY';
	my $highest = 0;
	my $final_path;
	for my $row ( @{$data} ) {
		my $num = int($row->{version} // 0);
		my $path = $row->{url} // '';
		next unless $path && $num > $highest;
		$highest = $num;
		$path .= '/' unless substr($path,-1,1) eq '/';
		$final_path = $path;
	}
	return $final_path;
}

# emit an error
sub _error {
	my ( $self, $error, $data ) = @_;
	$error = {} unless $error && ref($error) eq 'HASH';
	$data = [] unless $data && ref($data) eq 'ARRAY';
	$error->{code} ||= 500;
	$error->{message} ||= '';
	my $message = $error->{code}." ".$error->{message}.": ";
	for my $err ( @{$data} ) {
		$message .= ($err->{message} || '').': ';
		$message .= $err->{errorCode} ||= '';
	}
	$self->emit(error=>$message);
	return undef;
}

# Get the headers we need to send each time
sub _headers {
	my $self = shift;
	my $header = {
		Accept => 'application/json',
		DNT => 1,
		Date => Mojo::Date->new()->to_string(),
		'Sforce-Query-Options' => 'batchSize=2000',
		'Accept-Charset' => 'UTF-8',
	};
	return $header unless my $token = $self->_access_token;
	$header->{'Authorization'} = "Bearer $token";
	return $header;
}

# returns true (1) if login required, else undef
sub _login_required {
	my $self = shift;
	if( $self->_access_token && $self->api_host && $self->_api_path ) {
		if ( my $time = $self->_access_time ) {
			return undef if ( int((time() - $time)/60) < 30 );
		}
	}
	return 1;
}

# keep creating next delay steps until we have all of the query data.
sub _query_results_nb {
	my ($delay, $ua, $tx ) = @_;
	my $self = $delay->data('self') || die "Can't find SF object";
	my $cb = $delay->data('cb') || ($self->emit(error=>"Can't find callback") && return undef);
	return $self->_error($tx->error, $tx->res->json) unless $tx->success;
	my $data = $tx->res->json;
	my $records = $delay->data('records') || [];
	push @{$records}, @{$data->{records}};
	$delay->data(records=>$records);
	return $self->$cb($records) if $data->{done};
	return $self->$cb($records) unless $data->{nextRecordsUrl};
	my $url = Mojo::URL->new($self->api_host)->path($data->{nextRecordsUrl});
	$delay->steps(\&_query_results_nb);
	$self->ua->get($url, $self->_headers(), $delay->begin(0) );
}

1;


=encoding utf8

=head1 NAME

WWW::Salesforce - Perl communication with the Salesforce RESTful API

=head1 SYNOPSIS

Blocking:

	#!/usr/bin/env perl
	use Mojo::Base -strict;
	use WWW::Salesforce;
	use Data::Dumper;

	my $sf = WWW::Salesforce->new(
		api_host => Mojo::URL->new('https://ca13.salesforce.com'),
		consumer_key => 'alksdlkj3hasdg;jlaksghajdhgaghasdg.asdgfasodihgaopih.asdf',
		consumer_secret => 'asdfasdjkfh234123513245',
		username => 'foo@bar.com',
		password => 'mypassword',
		pass_token => 'mypasswordtoken123214123521345',
	);
	# handle any error events that get thrown (we'll just die for now)
	$sf->on(error => sub {my ($e, $err) = @_; die $err});

	say "Yay, we have a new SalesForce object!";

	# calling login() will happen automatically.
	my $records_array_ref = $sf->query('Select Id, Name, Phone from Account');
	say Dumper $records_array_ref;
	exit(0);

Non-blocking:

	#!/usr/bin/env perl
	use Mojo::Base -strict;
	use WWW::Salesforce;

	my $sf = WWW::Salesforce->new(
		api_host => Mojo::URL->new('https://ca13.salesforce.com'),
		consumer_key => 'alksdlkj3hasdg;jlaksghajdhgaghasdg.asdgfasodihgaopih.asdf',
		consumer_secret => 'asdfasdjkfh234123513245',
		username => 'foo@bar.com',
		password => 'mypassword',
		pass_token => 'mypasswordtoken123214123521345',
	);
	# handle any error events that get thrown (we'll just die for now)
	$sf->on(error => sub {my ($e, $err) = @_; die $err});

	# calling login() will happen automatically
	$sf->query('select Name from Account',sub {
		my ($self, $data) = @_;
		say scalar(@{$data}) if $data;
	});

=head1 DESCRIPTION

L<WWW::Salesforce> allows us to connect to L<Salesforce|http://www.salesforce.com/>'s service to access our data using their L<RESTful API|https://developer.salesforce.com/docs/atlas.en-us.api_rest.meta/api_rest/>.

Creation of a new L<WWW::Salesforce> instance will not actually hit the server.  The first communication with the L<Salesforce|http://www.salesforce.com/> API occurs when you specifically call the C<login> method or when you make another call.

All API calls using this library will first make sure you are properly logged in using L<Session ID Authorization|http://www.salesforce.com/us/developer/docs/api_rest/Content/quickstart_oauth.htm>, but more specifically, the L<Salesforce Username-Password OAuth Authentication Flow|http://www.salesforce.com/us/developer/docs/api_rest/Content/intro_understanding_username_password_oauth_flow.htm> to get your access token.
It will also make sure that you have grabbed the L<latest API version|http://www.salesforce.com/us/developer/docs/api_rest/Content/dome_versions.htm> and use that version for all subsequent API method calls.

=head1 EVENTS

L<WWW::Salesforce> can emit the following events via L<Mojo::UserAgent> which is ultimately a L<Mojo::EventEmitter>.

=head2 error

	$sf->on(error => sub {
		my ($e, $err) = @_;
		...
	});

This is a special event for errors.  It is fatal if unhandled and stops the current request otherwise. See L<Mojo::EventEmitter#error>.

=head1 ATTRIBUTES

L<WWW::Salesforce> makes the following attributes available.

=head2 api_host

	my $host = $sf->api_host;
	$host = $sf->api_host( Mojo::URL->new('https://test.salesforce.com') );

This is the base host of the API we're using.  This allows you to use any of your sandbox or live data areas easily.

Note, changing this attribute might invalidate your access token after you've logged in. You may want to C<logout> before changing this setting.

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

=head1 METHODS

L<WWW::Salesforce> makes the following methods available.

=head2 api_path

	# blocking
	my $path = $sf->api_path();

	# non-blocking
	$sf->api_path(
		my ($sf,$path) = @_;
		say "The api path is $path";
	);

This is the path to the API version we're using.  We're always going to be using the latest API version available.
On error, this method will emit an C<error> event. You should C<catch> errors as the caller.

=head2 catch

	$sf = $sf->catch(sub {...});

Subscribe to an C<error> event.  See L<Mojo::EventEmitter#catch>.

	# longer version
	$sf->on(error => sub {...});

=head2 emit

	$sf = $sf->emit('error');
	$sf = $sf->emit('error', "uh oh!");

Emit an event.

=head2 login

	# blocking
	$sf = $sf->login(); # allows for method-chaining

	# non-blocking
	$sf->login(
		my ($sf, $token) = @_;
		say "Our auth token is: $token";
	);

This method will and go through the L<Salesforce Username-Password OAuth Authentication Flow|http://www.salesforce.com/us/developer/docs/api_rest/Content/intro_understanding_username_password_oauth_flow.htm>
process if it needs to.
Calling this method on your own is not necessary as any API call will call C<login> if necessary.  This could be helpful if you're changing C<api_host>s on your instance.
This method will update your C<access_token> on a successful login.
On error, this method will emit an C<error> event. You should catch errors as the caller.

=head2 logout

	$sf = $sf->logout(); # allows for method chaining.

This method does not actually make any call to L<Salesforce|http://www.salesforce.com>.
It only removes knowledge of your access token so that you can login again on your next API call.

=head2 on

	$sf->on(error => sub {...});

Subscribe to an C<event>. See L<Mojo::EventEmitter#on>.

=head2 query

	# blocking
	my $results = $sf->query('Select Id, Name, Phone from Account');
	say Dumper $results;

	# non-blocking
	$sf->query('select Id, Name, Phone from Account', sub {
		my ($sf, $results) = @_;
		say Dumper $results;
	});

This method calls the Salesforce L<Query method|http://www.salesforce.com/us/developer/docs/api_rest/Content/resources_query.htm>.  It will keep grabbing and adding the records to your resultant array reference until there are no more records available to your query.
On error, this method will emit an C<error> event. You should catch errors as the caller.

=head1 ERROR HANDLING

Any and all errors that occur will emit an C<error> event. Events that aren't caught will trigger fatal exceptions. Catching errors is simple and allows you to log your error events any way you like:

	my $sf = WWW::Salesforce->new(...);
	$sf->catch(sub {
		my ($e, $error) = @_;
		# log it with whatever logging system you're using
		$log->error($error);
		# dump it to STDERR
		warn $error;
		# exit, maybe?
		exit(1);
	});
	my $result_wont_happen = $sf->query('bad query statement to produce error');

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
