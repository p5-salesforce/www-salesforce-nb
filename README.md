# www-salesforce-nb
A non-blocking [Salesforce API](https://developer.salesforce.com/docs/atlas.en-us.api_rest.meta/api_rest/intro_what_is_rest_api.htm) client using [Mojolicious](http://mojolicio.us). It may one day replace [WWW::Salesforce](http://metacpan.org/pod/WWW::Salesforce).

It is EXTREMELY experimental at this point.  Use it at your own risk.  You've been warned.

# Table of Contents

* [Synopsis](#synopsis)
* [Description](#description)
* [Events](#events)
* [Attributes](#attributes)
	* [api\_host](#api_host)
	* [consumer\_key](#consumer_key)
	* [consumer\_secret](#consumer_secret)
	* [pass\_token](#pass_token)
	* [password](#password)
	* [username](#username)
* [Methods](#methods)
	* [api\_path](#api_path)
	* [login](#login)
	* [logout](#logout)
	* [query](#query)
* [Author](#author)
* [Bugs](#bugs)

# SYNOPSIS

## Blocking way

```perl
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
$sf->on(error=> sub{ die pop });
# calling login() will happen automatically on any API call
my $records_array_ref = $sf->query('Select Id, Name, Phone from Account');
say Dumper $records_array_ref;
exit(0);
```

## Non-Blocking way

```perl
#!/usr/bin/env perl
use Mojo::Base -strict;
use Mojo::IOLoop;
use WWW::Salesforce;

Mojo::IOLoop->start unless Mojo::IOLoop->is_running;
my $sf = WWW::Salesforce->new(
	api_host => Mojo::URL->new('https://ca13.salesforce.com'),
	consumer_key => 'alksdlkj3hasdg;jlaksghajdhgaghasdg.asdgfasodihgaopih.asdf',
	consumer_secret => 'asdfasdjkfh234123513245',
	username => 'foo@bar.com',
	password => 'mypassword',
	pass_token => 'mypasswordtoken123214123521345',
);
$sf->catch(sub {die pop});

# calling login() will happen automatically on any API call
$sf->query('select Name from Account',sub {
	my ($self, $data) = @_;
	say "Found ".scalar(@{$data})." results" if $data;
});
```

# DESCRIPTION

The [WWW::Salesforce](https://github.com/genio/www-salesforce-nb/) class is a subclass of [Mojo::UserAgent](https://metacpan.org/pod/Mojo::UserAgent).  It implements all methods of [Mojo::UserAgent](https://metacpan.org/pod/Mojo::UserAgent) and adds a few more.

[WWW::Salesforce](https://github.com/genio/www-salesforce-nb/) allows us to connect to [Salesforce](http://www.salesforce.com/)'s service to get our data using their RESTful API.

Creation of a new [WWW::Salesforce](https://github.com/genio/www-salesforce-nb/) instance will not actually hit the server.  The first communication with the [Salesforce](http://www.salesforce.com/) API occurs when you specifically call the ```login``` method or when you make another call.

All API calls using this library will first make sure you are properly logged in using [Session ID Authorization](http://www.salesforce.com/us/developer/docs/api_rest/Content/quickstart_oauth.htm) to get your access token.
It will also make sure that you have grabbed the [latest API version](https://developer.salesforce.com/docs/atlas.en-us.api_rest.meta/api_rest/dome_versions.htm) and use that version for all subsequent API method calls.

The [Salesforce Username-Password OAuth Authentication Flow](http://www.salesforce.com/us/developer/docs/api_rest/Content/intro_understanding_username_password_oauth_flow.htm) can help you understand how we're connecting and maintaining our session.

# EVENTS

[WWW::Salesforce](https://github.com/genio/www-salesforce-nb/) inherits all events from [Mojo::UserAgent](https://metacpan.org/pod/Mojo::UserAgent).

# ATTRIBUTES

[WWW::Salesforce](https://github.com/genio/www-salesforce-nb/) inherits all attributes from [Mojo::UserAgent](https://metacpan.org/pod/Mojo::UserAgent) and adds the following new ones.

## api\_host

```perl
my $host = $sf->api_host;
$sf = $sf->api_host( Mojo::URL->new('https://test.salesforce.com') ); # allows for method-chaining
```

This is the base host of the API we're using.  This allows you to use any of your sandbox or live data areas easily.

Note, changing this attribute might invalidate your access token after you've logged in.

## consumer\_key

```perl
my $key = $sf->consumer_key;
$sf = $sf->consumer_key( 'alksdlksdf' ); # allows for method-chaining
```

The Consumer Key (also referred to as the client\_id in the Saleforce documentation) is part of your [Connected App](http://www.salesforce.com/us/developer/docs/api_rest/Content/intro_defining_remote_access_applications.htm).  It is a required field to be able to login.

Note, changing this attribute after the creation of your new instance is kind of pointless since it's only used to generate the access token at the beginning.

## consumer\_secret

```perl
my $secret = $sf->consumer_secret;
$sf = $sf->consumer_secret( 'asdfas123513245' ); # allows for method-chaining
```

The Consumer Secret (also referred to as the client\_secret in the Saleforce documentation) is part of your [Connected App](http://www.salesforce.com/us/developer/docs/api_rest/Content/intro_defining_remote_access_applications.htm).  It is a required field to be able to login.

Note, changing this attribute after the creation of your new instance is kind of pointless since it's only used to generate the access token at the beginning.

## pass\_token

```perl
my $token = $sf->pass_token;
$sf = $sf->pass_token( 'mypasswordtoken145' ); # allows for method-chaining
```

The password token is a Salesforce-generated token to go along with your password.  It is appended to the end of your password and used only during login authentication.

## password

```perl
my $password = $sf->password;
$sf = $sf->password( 'mypassword' ); # allows for method-chaining
```

The password is the password you set for your user account in Salesforce.  This attribute is only used during login authentication.

## username

```perl
my $username = $sf->username;
$sf = $sf->username( 'foo@bar.com' ); # allows for method-chaining
```

The username is the email address you set for your user account in Salesforce.  This attribute is only used during login authentication.

# METHODS

[WWW::Salesforce](https://github.com/genio/www-salesforce-nb/) inherits all methods from [Mojo::UserAgent](https://metacpan.org/pod/Mojo::UserAgent) and adds the following new ones.

## api\_path

```perl
# blocking
my $path = $sf->api_path();

# non-blocking
$sf->api_path(
	my ($sf,$path) = @_;
	say "The api path is $path";
);
```

This is the path to the API version we're using.  It's always the latest version of the [Salesforce API](https://developer.salesforce.com/docs/atlas.en-us.api_rest.meta/api_rest/dome_versions.htm).
On error, this method will emit an error event. You should ```perl $sf->catch( sub { say "Error: ".pop});``` errors as the caller.

## login

```perl
# blocking
$sf = $sf->login(); # allows for method-chaining

# non-blocking
$sf->login(
	my ($sf, $token) = @_;
	say "Our auth token is: $token";
);
```

This method will go through the [Salesforce Username-Password OAuth Authentication Flow](http://www.salesforce.com/us/developer/docs/api_rest/Content/intro_understanding_username_password_oauth_flow.htm) process if it needs to.
Calling this method on your own is not necessary as any API call will call ```login``` if necessary.  This could be helpful if you're changing ```api_host```s on your instance.
This method will update your ```access_token``` on a successful login.
On error, this method will emit an error event. You should ```$sf->catch( sub { say "Error: ".pop});``` errors as the caller.

## logout

```perl
$sf = $sf->logout(); # allows for method-chaining
```

This method does not actually make any call to [Salesforce](http://www.salesforce.com).
It only removes knowledge of your access token so that you can login again on your next API call.

## query

```perl
# blocking
my $results = $sf->query('Select Id, Name, Phone from Account');
say Dumper $results;

# non-blocking
$sf->query('select Id, Name, Phone from Account', sub {
	my ($sf, $results) = @_;
	say Dumper $results;
});
```

This method calls the Salesforce [Query method](http://www.salesforce.com/us/developer/docs/api_rest/Content/resources_query.htm).  It will keep grabbing and adding the records to your resultant array reference until there are no more records available to your query.
On error, this method will emit an error event. You should ```$sf->catch( sub { say "Error: ".pop});``` errors as the caller.

# AUTHOR

Chase Whitener -- cwhitener@gmail.com

# BUGS

Please report any bugs or feature requests on GitHub [https://github.com/genio/www-salesforce-nb/issues](https://github.com/genio/www-salesforce-nb/issues).
I appreciate any and all criticism, bug reports, enhancements, or fixes.
