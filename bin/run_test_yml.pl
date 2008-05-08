#!/usr/bin/env perl -w
use strict;
use Prophet::Test::Arena;

Prophet::Test::Arena->run_from_yaml;


=head1 NAME

run_test_yml - rerun recorded test

=head1 SYNOPSIS

  prove -l t/generalized_sync_n_merge.t
  perl -Ilib bin/run_test_yml.pl RECORDED-TEST.yml

=head1 DESCRIPTION

You can also copy this file to a .t file, and append the yml content into the
C<__DATA__> section.

=cut

