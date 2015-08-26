package WWW::Salesforce::Connector;

use Moo;
use Mojo::URL;
use Mojo::UserAgent;
use Scalar::Util;
use strictures 2;
use namespace::clean;

our @TYPES = qw(soap oauth2_up);

# attempt a login to Salesforce to obtain a token
sub login {
	my ($self,$sf, $cb) = @_;
	$cb = ($cb && ref($cb) eq 'CODE')? $cb: undef;
	unless ( $sf->_login_required ) {
		$sf->$cb(undef, $sf->_access_token) if $cb;
		return $sf;
	}
	my $method = '_login_'.$sf->login_type();
	return $self->$method($sf,$cb)
}
# log out of salesforce and invalidate the token we're using
sub logout {
	my ($self,$sf,$cb) = @_;
	$cb = ($cb && ref($cb) eq 'CODE')? $cb: undef;
	if ( $sf->_login_required ) {
		# we don't need to logout
		$sf->$cb(undef,1) if $cb;
		return $sf;
	}
	my $method = '_logout_'.$sf->login_type();
	return $self->$method($sf,$cb)
}

sub _login_oauth2_up {
	my ( $self, $sf, $cb ) = @_;
	my $url = Mojo::URL->new($sf->login_url)->path("/services/oauth2/token");
	my $form = {
		grant_type => 'password',
		client_id => $sf->consumer_key,
		client_secret => $sf->consumer_secret,
		username => $sf->username,
		password => $sf->password . $sf->pass_token,
	};
	# blocking request
	unless ($cb) {
		my $tx = $sf->ua->post($url, $sf->_headers(), form => $form);
		die $sf->_error($tx->error, $tx->res->json) unless $tx->success;
		my $data = $tx->res->json;
		$sf->_instance_url(Mojo::URL->new($data->{instance_url}));
		$sf->_access_token($data->{access_token});
		$sf->_access_time($data->{issued_at}/1000); #convert milliseconds to seconds
		return $sf;
	}

	# non-blocking request
	$sf->ua->post($url, $sf->_headers(), form => $form, sub {
		my ($ua, $tx) = @_;
		return $sf->$cb($sf->_error($tx->error, $tx->res->json),undef) unless $tx->success;
		my $data = $tx->res->json;
		$sf->_instance_url(Mojo::URL->new($data->{instance_url}));
		$sf->_access_token($data->{access_token});
		$sf->_access_time($data->{issued_at}/1000); #convert milliseconds to seconds
		return $sf->$cb(undef, $sf->_access_token);
	});
	return $sf;
}

sub _login_soap {
	my ( $self, $sf, $cb ) = @_;
	my $url = Mojo::URL->new($sf->login_url)->path($sf->_path_soap);
	my $user = $sf->username;
	my $pass = $sf->password . $sf->pass_token;
	my $envelope = qq(<?xml version="1.0" encoding="utf-8"?><soapenv:Envelope xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/" xmlns:urn="urn:partner.soap.sforce.com"><soapenv:Body><urn:login><urn:username>$user</urn:username><urn:password>$pass</urn:password></urn:login></soapenv:Body></soapenv:Envelope>);
	my $headers = {
		Accept => 'text/xml',
		'Content-Type' => 'text/xml; charset=utf-8',
		DNT => 1,
		'Sforce-Query-Options' => 'batchSize=2000',
		'Accept-Charset' => 'UTF-8',
		SOAPAction => '""',
		Expect => '100-continue',
		Host => Mojo::URL->new($sf->login_url)->host,
	};
	unless ( $cb ) {
		my $tx = $sf->ua->post($url, $headers, $envelope);
		die $self->_soap_error($tx->error, $tx->res->dom) unless $tx->success;
		my $data = $self->_soap_parse_login_response($tx->res->dom);
		$sf->_instance_url(Mojo::URL->new($data->{serverUrl}));
		$sf->_access_token($data->{sessionId});
		$sf->_access_time(time);
		return $sf;
	}
	# non-blocking request
	$sf->ua->post($url,$headers, $envelope, sub {
		my ($ua, $tx) = @_;
		return $sf->$cb($sf->_soap_error($tx->error, $tx->res->dom),undef) unless $tx->success;
		my $data = $self->_soap_parse_login_response($tx->res->dom);
		$sf->_instance_url(Mojo::URL->new($data->{serverUrl}));
		$sf->_access_token($data->{sessionId});
		$sf->_access_time(time); #convert milliseconds to seconds
		return $sf->$cb(undef, $sf->_access_token);
	});
	return $sf;
}

sub _logout_oauth2_up {
	my ($self, $sf, $cb) = @_;
	my $url = Mojo::URL->new($sf->_instance_url)->path("/services/oauth2/revoke");
	#blocking request
	unless ( $cb ) {
		my $tx = $sf->ua->post($url, $sf->_headers(), form =>{token=>$sf->_access_token});
		die $sf->_error($tx->error, $tx->res->json) unless $tx->success;
		$sf->_instance_url(undef);
		$sf->_path(undef);
		$sf->_access_token(undef);
		$sf->_access_time(0);
		return $sf;
	}
	# non-blocking request
	$sf->ua->post($url, $sf->_headers(), form =>{token=>$sf->_access_token}, sub {
		my ($ua, $tx) = @_;
		return $sf->$cb($sf->_error($tx->error, $tx->res->json),undef) unless $tx->success;
		$sf->_instance_url(undef);
		$sf->_path(undef);
		$sf->_access_token(undef);
		$sf->_access_time(0);
		return $sf->$cb(undef, 1);
	});
	return $sf;
}

sub _soap_error {
	my ( $self, $error, $data ) = @_;
	my $message = '';
	if ( $error && ref($error) eq 'HASH' ) {
		$message .= sprintf("%s %s: ", $error->{code} || "500", $error->{message} || '');
	}
	return '' unless $message;
	# no need to traverse the data if there's no error.
	if ( $data && Scalar::Util::blessed($data) && $data->isa('Mojo::DOM') ) {
		$message .= sprintf("%s: %s", $data->at('faultcode')->text()||'',$data->at('faultstring')->text()||'');
	}
	return $message;
}
sub _soap_parse_login_response {
	my ( $self, $dom ) = @_;
	my $info = {userInfo=>{},};
	$dom->at('userInfo')->child_nodes->each(sub {
		my $element = shift;
		$info->{userInfo}{$element->tag()} = $element->text() || '';
	});
	$dom->at('userInfo')->remove;
	$dom->at('result')->child_nodes->each(sub {
		$info->{$_[0]->tag()}=$_[0]->text()||'';
	});
	return $info;
}
1;

=encoding utf8

=head1 NAME

WWW::Salesforce::Connector - Handle your connection to the Salesforce API

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

L<WWW::Salesforce::Connector> is used by L<WWW::Salesforce> to handle your connection via the method of your choice.

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
