use Module::Build;

my $build = Module::Build->new(
			       module_name => 'MP3::PodcastFetch',
			       license     => 'perl',
			       requires => {
					    perl               => '5.8',
					    LWP                => '5.8',
					    'HTML::Parser'     => '3.50',
					    'Config::IniFiles' => '2.00',
					    },
			       PL_files => {
					    'bin/fetch_pods.PLS' => 'bin/fetch_pods.pl',
					    },
			       script_files => ['bin/fetch_pods.pl'],
			      );
$build->create_build_script;
exit 0;
