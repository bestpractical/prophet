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
        recommends('HTTP::Server::Simple'), # HTTP::Server::Simple::CGI
        recommends('Test::HTTP::Server::Simple'),
        recommends('Test::WWW::Mechanize' => '1.16'),
        recommends('HTTP::Server::Simple')
    ],


    'Subversion replica support' => [
        -default => 0,
        recommends( 'SVN::Core') # SVN::Repos SVN::Fs SVN::Ra SVN::Delta::Editor SVN::Client SVN::Delta
    ],
    'Crazy debugging tools' => [
        -default   => 1,
        recommends('Acme::MetaSyntactic'),
        recommends('Devel::Gladiator')
    ],
    'Testing' => [
        -default => 1,
        'YAML::Syck' => 0
    ]
);

all_from('lib/Prophet.pm');
auto_install;
WriteAll();
