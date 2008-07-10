#!/usr/bin/perl
#
use inc::Module::Install;
name('Prophet');
author('clkao and jesse');
license('Perl');

requires('Params::Validate');
requires('List::MoreUtils');
requires('Class::Accessor');
requires('IPC::Run3');
requires('Data::UUID');
requires('Path::Class');
requires('Test::Exception');
requires('UNIVERSAL::require');
requires('Term::ReadKey');
requires('Digest::SHA1');  # Core in 5.10
requires('LWP::Simple'); # Part of lib-www-perl
requires('URI');
requires('JSON');
requires('Module::Pluggable');
requires('File::Find::Rule');
requires('Proc::InvokeEditor');
requires('Scalar::Defer');
requires('Moose'); # Moose::Util::TypeConstraints Moose::Role
requires('MooseX::AttributeHelpers');
requires('MooseX::ClassAttribute');

features(
    'REST Server' => [
        -default => 1,
        'HTTP::Server::Simple', # HTTP::Server::Simple::CGI
        'Test::HTTP::Server::Simple',
        'Test::WWW::Mechanize' => '1.16',
        'HTTP::Server::Simple'
    ],


    'Subversion replica support' => [
        -default => 0,
         'SVN::Core' # SVN::Repos SVN::Fs SVN::Ra SVN::Delta::Editor SVN::Client SVN::Delta
    ],
    'Maintainer testing tools' => [
        -default   => 1,
        'Acme::MetaSyntactic',
        'Test::Pod::Coverage'
    ],
    q{Devel::Gladiator support (contact sky@crucially.net if it's not on CPAN)} => [
        -default => 0,
        'Devel::Gladiator'
    ],
    'Testing' => [
        -default => 1,
        'YAML::Syck' => 0
    ]
);

all_from('lib/Prophet.pm');
auto_install;
WriteAll();
