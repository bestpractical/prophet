#!/usr/bin/perl
#
use inc::Module::Install;
name('Prophet');
author('clkao and jesse');
license('Perl');

requires('Params::Validate');
requires('IPC::Run3');
requires('Data::UUID');
requires('Path::Class');
build_requires('Test::Exception');
requires('Term::ReadKey');
requires('Digest::SHA1');  # Core in 5.10
requires('LWP::Simple'); # Part of lib-www-perl
requires('URI');
requires('JSON' => '2.00');
requires('Module::Pluggable');
requires('File::Find::Rule');
requires('Proc::InvokeEditor');
requires('Scalar::Defer');
requires('Moose' => '0.54'); # Moose::Util::TypeConstraints Moose::Role
requires('MooseX::AttributeHelpers' => '0.12');
requires('MooseX::ClassAttribute' => '0.04');
requires('XML::Atom::SimpleFeed');
requires('Path::Dispatcher'); # Path::Dispatcher::Declarative

use Term::ReadLine; # if we don't do this, ::Perl fails
features(
    'Improved interactive shell' => [
        -default => 1,
        'Term::ReadLine::Perl'
        ],
    'Web server' => [
        -default => 1,
        'HTTP::Server::Simple', # HTTP::Server::Simple::CGI
    ],

    'HTML display' => [
        -default => 1,
        'Template::Declare', # Template::Declare::Tags
    ],

    'Subversion replica support' => [
        -default => 0,
         'SVN::Core' # SVN::Repos SVN::Fs SVN::Ra SVN::Delta::Editor SVN::Client SVN::Delta
    ],
    'Maintainer testing tools' => [
        -default   => 1,
        'Test::HTTP::Server::Simple',
        'Acme::MetaSyntactic',
        'YAML::Syck' => 0,
        'Test::WWW::Mechanize' => '1.16',
        'Test::Pod::Coverage'
    ],
#    q{Devel::Gladiator support (contact sky@crucially.net if it's not on CPAN)} => [
#        -default => 0,
#        'Devel::Gladiator'
#    ],
    'Bonjour support' => [
        -default => 0,
        'Net::Bonjour',
    ],
);

all_from('lib/Prophet.pm');
install_script('bin/prophet');
auto_install;
WriteAll();
