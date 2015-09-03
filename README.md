# www-salesforce-nb [![Build Status](https://travis-ci.org/genio/www-salesforce-nb.svg?branch=master)](https://travis-ci.org/genio/www-salesforce-nb)

A non-blocking [Salesforce API](https://developer.salesforce.com/docs/atlas.en-us.api_rest.meta/api_rest/intro_what_is_rest_api.htm) client using [Mojolicious](http://mojolicio.us). It may one day replace [WWW::Salesforce](http://metacpan.org/pod/WWW::Salesforce).

It is EXTREMELY experimental at this point.  Use it at your own risk.  You've been warned.

## Table of Contents

* [Synopsis](#synopsis)
* [Description](#description)
* [Events](#events)
* [Attributes](#attributes)
	* [consumer\_key](#consumer_key)
	* [consumer\_secret](#consumer_secret)
	* [login\_type](#login_type)
		* [oauth2\_up](#oauth2_up)
		* [soap](#soap)
	* [login\_url](#login_url)
	* [pass\_token](#pass_token)
	* [password](#password)
	* [ua](#ua)
	* [username](#username)
	* [version](#version)
* [Methods](#methods)
	* [create](#create)
	* [describe](#describe)
	* [limits](#limits)
	* [login](#login)
	* [logout](#logout)
	* [query](#query)
	* [retrieve](#retrieve)
	* [search](#search)
* [Error Handling](#error-handling)
* [Author](#author)
* [Bugs](#bugs)

## SYNOPSIS

```perl
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
```

## DESCRIPTION

[WWW::Salesforce](https://github.com/genio/www-salesforce-nb/) allows us to connect to [Salesforce](http://www.salesforce.com/)'s service to access our data using their [RESTful API](https://developer.salesforce.com/docs/atlas.en-us.api_rest.meta/api_rest/).

Creation of a new [WWW::Salesforce](https://github.com/genio/www-salesforce-nb/) instance will not actually hit the server.  The first communication with the [Salesforce](http://www.salesforce.com/) API occurs when you specifically call the ```login``` method or when you make another call.

All API calls using this library will first make sure you are properly logged in.

* ```oauth2_up``` OAuth2 using the username and password (up) method:
	* [Session ID Authorization](https://developer.salesforce.com/docs/atlas.en-us.api_rest.meta/api_rest/quickstart_oauth.htm)
	* [Salesforce Username-Password OAuth Authentication Flow](https://developer.salesforce.com/docs/atlas.en-us.api_rest.meta/api_rest/intro_understanding_username_password_oauth_flow.htm)
* ```soap``` Alternately, you can use the soap login method:
	* [Salesforce SOAP-based username and password login flow](https://developer.salesforce.com/docs/atlas.en-us.api.meta/api/sforce_api_calls_login.htm)

## ATTRIBUTES

[WWW::Salesforce](https://github.com/genio/www-salesforce-nb/) makes the following attributes available.

### consumer\_key

```perl
my $key = $sf->consumer_key;
$key = $sf->consumer_key( 'alksdlksdf' );
```

The Consumer Key (also referred to as the client\_id in the Saleforce documentation) is part of your [Connected App](http://www.salesforce.com/us/developer/docs/api_rest/Content/intro_defining_remote_access_applications.htm).  It is a required field to be able to login.

Note, this attribute is only used to generate the access token during [login](#login).  You may want to [logout](#logout) before changing this setting.

### consumer\_secret

```perl
my $secret = $sf->consumer_secret;
$secret = $sf->consumer_secret( 'asdfas123513245' );
```

The Consumer Secret (also referred to as the client\_secret in the Saleforce documentation) is part of your [Connected App](http://www.salesforce.com/us/developer/docs/api_rest/Content/intro_defining_remote_access_applications.htm).  It is a required field to be able to login.

Note, this attribute is only used to generate the access token during [login](#login).  You may want to [logout](#logout) before changing this setting.

### login\_type

```perl
my $type = $sf->login_type;
$type = $sf->login_type( 'oauth2_up' );
```

This is what will determine our login method of choice. No matter which login method you choose, we're going to communicate to the Salesforce services using an ```Authorization: Bearer token``` header. The login method just dictates how we will request that token from Salesforce.  Different methods of login require slightly different sets of data in order for the login to take place.

You may want to [logout](#logout) before changing this setting.

Available types are:

#### oauth2_up

This login type is the default.  It will require your [consumer\_key](#consumer_key), [consumer\_secret](#consumer_secret), [username](#username), [password](#password), [pass\_token](#pass_token) and [login\_url](#login_url).  This method will go through the [Salesforce Username-Password OAuth Authentication Flow](http://www.salesforce.com/us/developer/docs/api_rest/Content/intro_understanding_username_password_oauth_flow.htm).


#### soap

This method will only require your [username](#username), [password](#password), [pass\_token](#pass_token) and [login\_url](#login_url). It will go through the [Salesforce SOAP-based username and password login flow](https://developer.salesforce.com/docs/atlas.en-us.api.meta/api/sforce_api_calls_login.htm).

### login\_url

```perl
my $host = $sf->login_url;
$host = $sf->login_url( Mojo::URL->new('https://test.salesforce.com') );
```

This is the base host of the API we're using.  This allows you to use any of your sandbox or live data areas easily. You may want to [logout](#logout) before changing this setting.

### pass\_token

```perl
my $token = $sf->pass_token;
$token = $sf->pass_token( 'mypasswordtoken145' );
```

The password token is a Salesforce-generated token to go along with your password.  It is appended to the end of your password and used only during [login](#login) authentication.

Note, this attribute is only used to generate the access token during [login](#login).  You may want to [logout](#logout) before changing this setting.

### password

```perl
my $password = $sf->password;
$password = $sf->password( 'mypassword' );
```

The password is the password you set for your user account in Salesforce.

Note, this attribute is only used to generate the access token during [login](#login).  You may want to [logout](#logout) before changing this setting.

### ua

```perl
my $ua = $sf->ua;
```

The [Mojo::UserAgent](https://metacpan.org/pod/Mojo::UserAgent) is the user agent we use to communicate with the Salesforce services.  For ```proxy``` and other needs, see the [Mojo::UserAgent](https://metacpan.org/pod/Mojo::UserAgent) documentation.

### username

```perl
my $username = $sf->username;
$username = $sf->username( 'foo@bar.com' );
```

The username is the email address you set for your user account in Salesforce.
Note, this attribute is only used to generate the access token during [login](#login).  You may want to [logout](#logout) before changing this setting.

### version

```perl
my $version = $sf->version;
$version = $sf->version( '34.0' );
```

Tell us what API version you'd like to use.  Leave off the ```v``` from the version number.


## METHODS

[WWW::Salesforce](https://github.com/genio/www-salesforce-nb/) makes the following methods available.

### create

```perl
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
```

This method calls the Salesforce [Create method](https://developer.salesforce.com/docs/atlas.en-us.api_rest.meta/api_rest/dome_sobject_create.htm).
On a successful transaction, a JSON response is returned with three fields (```id```, ```success```, and ```errors```).  You should check that response to see if your creation attempt actually succeeded.

### describe

```perl
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
```

This method calls the Salesforce [Describe method](https://developer.salesforce.com/docs/atlas.en-us.api_rest.meta/api_rest/resources_sobject_describe.htm).
On a successful transaction, a JSON response is returned with data full of useful information about the SObject.

### limits

```perl
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
```

This method calls the Salesforce [Limits method](https://developer.salesforce.com/docs/atlas.en-us.api_rest.meta/api_rest/resources_limits.htm).

### login

```perl
## blocking
$sf = $sf->login(); # allows for method-chaining

## non-blocking
$sf->login( sub {
	my ($sf, $token) = @_;
	say "Our auth token is: $token";
});
```

This method will go through the [Salesforce Username-Password OAuth Authentication Flow](http://www.salesforce.com/us/developer/docs/api_rest/Content/intro_understanding_username_password_oauth_flow.htm) process if it needs to.
Calling this method on your own is not necessary as any API call will call ```login``` if necessary.  This could be helpful if you're changing ```api_host```s on your instance.
This method will update your ```access_token``` on a successful login.

### logout

```perl
$sf = $sf->logout(); # allows for method-chaining
```

This method does not actually make any call to [Salesforce](http://www.salesforce.com).
It only removes knowledge of your access token so that you can login again on your next API call.

### query

```perl
## blocking
my $results = $sf->query('Select Id, Name, Phone from Account');
say Dumper $results;

## non-blocking
$sf->query('select Id, Name, Phone from Account', sub {
	my ($sf, $results) = @_;
	say Dumper $results;
});
```

This method calls the Salesforce [Query method](http://www.salesforce.com/us/developer/docs/api_rest/Content/resources_query.htm).  It will keep grabbing and adding the records to your resultant array reference until there are no more records available to your query.

Your query string must be in the form of an [SOQL String](https://developer.salesforce.com/docs/atlas.en-us.soql_sosl.meta/soql_sosl/sforce_api_calls_soql_select.htm).

### retrieve

```perl
# blocking
try {
	my $results = $sf->retrieve('Account','01231ABCDFQ2100002', [qw(Optional FieldName List Here)]);
	# can also call as ->retrieve('Account','01231ABCDFQ2100002')
	say Dumper $results;
} catch {
	die "Errors: $_";
};

# non-blocking
$sf->retrieve('Account','01231ABCDFQ2100002', [qw(Optional FieldName List Here)], sub {
	# can also call as ->retrieve('Account','01231ABCDFQ2100002', sub {...});
	my ($sf, $err, $results) = @_;
	say Dumper $results;
});
```

This method calls the Salesforce [Retrieve method](https://developer.salesforce.com/docs/atlas.en-us.api_rest.meta/api_rest/dome_get_field_values.htm).

### search

```perl
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
```

This method calls the Salesforce [Search method](https://developer.salesforce.com/docs/atlas.en-us.api_rest.meta/api_rest/resources_search.htm).
Your search query must be in the form of an [SOSL String](https://developer.salesforce.com/docs/atlas.en-us.soql_sosl.meta/soql_sosl/sforce_api_calls_sosl_syntax.htm).

## ERROR HANDLING

All blocking method calls will ```die``` on error and thus you should use [Try::Tiny](https://metacpan.org/pod/Try::Tiny) a lot.

```perl
# blocking call
use Try::Tiny qw(try catch);
try {
	my $res = $sf->do_something();
} catch {
	die "uh oh: $_";
};
```

All non-blocking methods will return an error string to the callback if there is one:

```perl
# non-blocking call
$sf->do_something(sub {
	my ( $instance, $error_string, $results ) = @_;
	die "uh oh: $error_string" if $error_string;
});
```

## AUTHOR

Chase Whitener -- cwhitener@gmail.com

## BUGS

Please report any bugs or feature requests on GitHub [https://github.com/genio/www-salesforce-nb/issues](https://github.com/genio/www-salesforce-nb/issues).
I appreciate any and all criticism, bug reports, enhancements, or fixes.
