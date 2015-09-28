package WWW::Salesforce::Connector;

use strictures 2;
use Mojo::URL ();
use Mojo::Util qw(xml_escape);
use Scalar::Util ();
use WWW::Salesforce::SOAP;

use Moo::Role;
use 5.010;
has '_access_token' => (is=>'rw',default=>'');
has '_access_time' => (is=>'rw',lazy=>1,default=>sub{time()});
has '_instance_url' => (is => 'rw', default => '');
has '_soap' => (is => 'ro',required => 1,default => sub {WWW::Salesforce::SOAP->new();},);

# attempt a login to Salesforce to obtain a token
sub login {
	my ($self, $cb) = @_;
	$cb = ($cb && ref($cb) eq 'CODE')? $cb: undef;
	unless ( $self->_login_required ) {
		$self->$cb(undef, $self->_access_token) if $cb;
		return $self;
	}
	my $type = $self->login_type() || 'oauth2_up';
	return $self->_login_soap($cb) if $type eq 'soap';
	return $self->_login_oauth2_up($cb)
}
# log out of salesforce and invalidate the token we're using
sub logout {
	my ($self,$cb) = @_;
	$cb = ($cb && ref($cb) eq 'CODE')? $cb: undef;
	if ( $self->_login_required ) {
		# we don't need to logout
		$self->$cb(undef,1) if $cb;
		return $self;
	}
	my $headers = $self->_headers();
	$headers->{content_type} = 'application/x-www-form-urlencoded';
	my $url = Mojo::URL->new($self->_instance_url)->path("/services/oauth2/revoke");
	#blocking request
	unless ( $cb ) {
		my $tx = $self->ua->post($url, $self->_headers(), form =>{token=>$self->_access_token});
		die $self->_error($tx) unless $tx->success;
		$self->_instance_url(undef);
		$self->_path(undef);
		$self->_access_token(undef);
		$self->_access_time(0);
		$self->ua->cookie_jar->empty();
		return $self;
	}
	# non-blocking request
	$self->ua->post($url, $self->_headers(), form =>{token=>$self->_access_token}, sub {
		my ($ua, $tx) = @_;
		return $self->$cb($self->_error($tx),undef) unless $tx->success;
		$self->_instance_url(undef);
		$self->_path(undef);
		$self->_access_token(undef);
		$self->_access_time(0);
		$self->ua->cookie_jar->empty();
		return $self->$cb(undef, 1);
	});
	return $self;
}

sub _login_oauth2_up {
	my ( $self, $cb ) = @_;
	my $url = Mojo::URL->new($self->login_url)->path("/services/oauth2/token");
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
		die $self->_error($tx) unless $tx->success;
		my $data = $tx->res->json;
		$self->_instance_url(Mojo::URL->new($data->{instance_url}));
		$self->_access_token($data->{access_token});
		$self->_access_time($data->{issued_at}/1000); #convert milliseconds to seconds
		return $self;
	}

	# non-blocking request
	$self->ua->post($url, $self->_headers(), form => $form, sub {
		my ($ua, $tx) = @_;
		return $self->$cb($self->_error($tx),undef) unless $tx->success;
		my $data = $tx->res->json;
		$self->_instance_url(Mojo::URL->new($data->{instance_url}));
		$self->_access_token($data->{access_token});
		$self->_access_time($data->{issued_at}/1000); #convert milliseconds to seconds
		return $self->$cb(undef, $self->_access_token);
	});
	return $self;
}

# returns true (1) if login required, else undef
sub _login_required {
	my $self = shift;
	if( $self->_access_token && $self->_instance_url && $self->_path ) {
		if ( my $time = $self->_access_time ) {
			return undef if ( int((time() - $time)/60) < 30 );
		}
	}
	$self->ua->cookie_jar->empty();
	return 1;
}

sub _login_soap {
	my ( $self, $cb ) = @_;
	my $url = Mojo::URL->new($self->login_url)->path($self->_path('soap'));
	my $envelope = $self->_soap->envelope_login($self->username, $self->password, $self->pass_token)->to_string;

	unless ( $cb ) {
		my $tx = $self->ua->post($url, $self->_headers('soap'), $envelope);
		die $self->_error($tx) unless $tx->success;
		my $data = $self->_soap->response_login($tx->res->dom);
		$self->_instance_url(Mojo::URL->new($data->{serverUrl}));
		$self->_access_token($data->{sessionId});
		$self->_access_time(time);
		return $self;
	}
	# non-blocking request
	$self->ua->post($url,$self->_headers('soap'), $envelope, sub {
		my ($ua, $tx) = @_;
		#use Data::Dumper; say Dumper $tx->res; exit(0);
		return $self->$cb($self->_error($tx),undef) unless $tx->success;
		my $data = $self->_soap->response_login($tx->res->dom);
		$self->_instance_url(Mojo::URL->new($data->{serverUrl}));
		$self->_access_token($data->{sessionId});
		$self->_access_time(time); #convert milliseconds to seconds
		return $self->$cb(undef, $self->_access_token);
	});
	return $self;
}


1;

=encoding utf8

=head1 NAME

WWW::Salesforce::Connector - A role to handle some of the implementation of WWW::Salesforce

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
		login_type => 'oauth2_up',
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

L<WWW::Salesforce::Connector> is a L<Moo::Role> that implements the C<login> and C<logout> methods.

=head1 ATTRIBUTES

L<WWW::Salesforce::Connector> makes the following attributes available.

=head1 METHODS

L<WWW::Salesforce::Connector> makes the following methods available.

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
