use SVN::Simple::Edit;
           require SVN::Core;
           require SVN::Repos;
           require SVN::Fs;
use Data::Dumper;
    $repospath = "/tmp/repo-".$$;
    `svnadmin create $repospath`;

           $repos = SVN::Repos::open($repospath);
$fs = $repos->fs;

        $edit = SVN::Simple::Edit->new(_editor => [SVN::Repos::get_commit_editor($repos, "file://$repospath",
                                             '/', 'root', 'FOO', \&committed)],
           );
    $checksum = '1234';
        $edit->open_root($fs->youngest_rev);
        $edit->add_directory ('trunk');
        $edit->add_file ('trunk/filea');
        $edit->modify_file ("trunk/filea", "content", $checksum);
        $edit->close_edit ();


        sub committed {
    warn Dumper(\@_);
        }
