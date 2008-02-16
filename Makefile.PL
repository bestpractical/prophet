#!/usr/bin/perl
#
use inc::Module::Install;

requires('SVN::Core');
all_from('lib/SVN/PropDB.pm');

WriteAll();
