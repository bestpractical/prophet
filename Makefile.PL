#!/usr/bin/perl
#
use inc::Module::Install;
name('Prophet');
author('clkao and jesse');
license('DeathandRepudiation');
requires('Params::Validate');
requires('List::MoreUtils');
requires('Class::Accessor');
requires('IPC::Run3');
requires('Test::Exception');
requires('Data::UUID');
requires('Path::Class');
requires('YAML::Syck');
requires('Test::Exception');
requires('Acme::MetaSyntactic');
requires('UNIVERSAL::require');
requires('App::Cache');
requires('Class::Data::Inheritable');
requires('DateTime::Format::HTTP');
requires('Devel::Gladiator');
requires('RT::Client::REST');
requires('RT::Client::REST::Ticket');
requires('RT::Client::REST::User');
requires('SVB::Record');
requires('Term::ReadKey');
requires('Digest::SHA1');
requires('LWP::Simple');
requires('URI');
requires('JSON');
requires('Test::HTTP::Server::Simple');
requires('HTTP::Server::Simple');
requires('Test::WWW::Mechanize');
requires('HTTP::Server::Simple::CGI');
requires('SVN::Core');    # SVN::Repos SVN::Fs SVN::Ra SVN::Delta::Editor SVN::Client SVN::Delta
features(
    'Crazy debugging tools' => [
        -default   => 1,
        recommends => 'Devel::Gladiator'
    ],
    'Hiveminder sync' => [
        -default => 0,
        requires => 'Net::Jifty',
        requires => 'Jifty',
    ]
);

all_from('lib/Prophet.pm');

WriteAll();
