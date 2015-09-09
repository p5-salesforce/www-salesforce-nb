package WWW::Salesforce::SOAP;

use Moo;
use strictures 2;
use Mojo::DOM ();
use Mojo::Util qw(xml_escape);
use 5.010;
use namespace::clean;

has urn => (is=>'rw',default=>'urn:partner.soap.sforce.com');

sub envelope {
	my $self = shift;
	my $dom = Mojo::DOM->new->xml(1)->parse('<?xml version="1.0" encoding="utf-8"?><soapenv:Envelope />');
	$dom->at('soapenv\:Envelope')->attr(
		'xmlns:soapenv' => "http://schemas.xmlsoap.org/soap/envelope/",
		'xmlns:urn' => $self->urn,
	);
	$dom->at('soapenv\:Envelope')->content('<soapenv:Header /><soapenv:Body />');
	return $dom;
}

sub envelope_login {
	my ( $self, $user, $pass, $token ) = @_;
	my $dom = $self->envelope;
	$dom->at('soapenv\:Header')->remove;
	$dom->at('soapenv\:Body')->content('<urn:login><urn:username /><urn:password /></urn:login>');
	$dom->at('urn\:username')->content(xml_escape($user || ''));
	$dom->at('urn\:password')->content(xml_escape($pass || '').xml_escape($token || ''));
	return $dom;
}

sub error_string {
	my ( $self, $error, $data ) = @_;
	my $message = '';
	if ( $error && ref($error) eq 'HASH' ) {
		$message .= sprintf("%s %s: ", $error->{code} || "500", $error->{message} || '');
	}
	return '' unless $message;
	# no need to traverse the data if there's no error.
	if ( $data && Scalar::Util::blessed($data) && $data->isa('Mojo::DOM') ) {
		if ( $data->at('faultcode') && $data->at('faultstring') ) {
			$message .= sprintf("%s: %s", $data->at('faultcode')->text(),$data->at('faultstring')->text());
		}
	}
	return $message;
}

sub response_login {
	my ( $self, $dom ) = @_;
	my $info = {userInfo=>{},};
	$dom->at('loginResponse > result')->child_nodes->each(sub {
		my $element = shift;
		my $tag = $element->tag();
		return unless $tag;
		my $count = 0;
		$element->child_nodes->each(sub {
			my $uinfo = shift;
			my $utag = $uinfo->tag();
			return unless $utag;
			$count++;
			$info->{$tag} //= {};
			$info->{$tag}{$utag} = $uinfo->text() || '';
		});
		unless ( $count ) {
			$info->{$tag} = $element->text() || '';
		}
	});
	return $info;
}

1;

=encoding utf8

=head1 NAME

WWW::Salesforce::SOAP - Handle some of the mundane tasks of SOAP calls

=head1 SYNOPSIS

	my $soap = WWW::Salesforce::SOAP->new();
	say $soap->enveople_login('username','password','pass_token')->to_string();

=head1 DESCRIPTION

L<WWW::Salesforce::SOAP> allows us to pull a lot of the mundane code out that only deals with SOAP transactions.

=head1 ATTRIBUTES

L<WWW::Salesforce::SOAP> makes the following attributes available.

=head2 urn

	my $urn = $soap->urn;
	$urn = $sf->urn( 'urn:partner.soap.sforce.com' );

The C<urn> allows

=head1 METHODS

L<WWW::Salesforce::SOAP> makes the following methods available.

=head2 envelope

Returns a L<Mojo::DOM> object of a basic envelope for your SOAP transaction.

=head2 envelope_login

Returns a L<Mojo::DOM> object of a login envelope for your SOAP login transaction.

=head2 error_string

Parses the SOAP response from Salesforce and gives you the error string from it.

=head2 response_login

Parses the SOAP response from Salesforce and gives you a hash ref representation.

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
