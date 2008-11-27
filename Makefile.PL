#!/usr/bin/perl
#
use inc::Module::Install;
name('Prophet'); #  App::Settings App::Settings::CLI App::WebToy App::WebToy::CLI
author('clkao and jesse');
license('Perl');

requires('Params::Validate');
requires('IPC::Run3');
requires('Data::UUID');
requires('Digest::SHA1');  # Core in 5.10
requires('LWP::Simple'); # Part of lib-www-perl
requires('URI');
requires('JSON' => '2.00');
requires('Module::Pluggable');
requires('File::Find::Rule');
requires('Proc::InvokeEditor');
requires('Scalar::Defer' => '0.18');
requires('Class::MOP' => '0.70');
requires('Moose' => '0.61'); # Moose::Util::TypeConstraints Moose::Role
requires('MooseX::AttributeHelpers' => '0.12');
requires('MooseX::ClassAttribute' => '0.04');
requires('XML::Atom::SimpleFeed');
requires('Path::Dispatcher' => '0.06'); # Path::Dispatcher::Declarative
requires('Time::Progress');

build_requires('Test::Exception' => '0.26');

use Term::ReadLine; # if we don't do this, ::Perl fails
features(
    'Improved interactive shell' => [
        -default => 1,
        'Term::ReadLine::Perl'
        ],
    'Faster JSON Parsing' => [
        -default => 1,
        'JSON::XS', => '2.2222'
    ],
    'Web server' => [
        -default => 1,
        'HTTP::Server::Simple', # HTTP::Server::Simple::CGI
    ],

    'HTML display' => [
        -default => 1,
        'Template::Declare', # Template::Declare::Tags
    ],
    'Foreign replica support' => [
        -default => 1,
        'Term::ReadKey'
    ],
    'Subversion replica support' => [
        -default => 0,
         'SVN::Core',  # SVN::Repos SVN::Fs SVN::Ra SVN::Delta::Editor SVN::Client SVN::Delta
         'Term::ReadKey',
    ],
    'Maintainer testing tools' => [
        -default   => 1,
        'Test::HTTP::Server::Simple',
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
        'Net::Bonjour', # Net::Rendezvous::Publish
    ],
);

tests('t/*.t t/*/t/*.t');
all_from('lib/Prophet.pm'); 
install_script('bin/prophet');
auto_install;
WriteAll();
