# vi: filetype=perl6:
my $out := '';

sub out(*@args) {
    $out := $out ~ nqp::join('', @args) ~ "\n";
}

sub comment($comment) {
    out("# $comment");
}
sub constant($name, $value) {
    out("$name = $value");
}

sub nfp ($file) {
    if $file ~~ /\// {
        return '@nfp(' ~ $file ~ ')@'
    }
    $file
}

sub stage_path($stage) {
    '$(JS_STAGE' ~ $stage ~ ')/';
}

sub make_parents($path) {
    my $parts := nqp::split("/",$path);
    nqp::pop($parts);
    '$(MKPATH) ' ~ nfp(nqp::join('/',$parts));
}

sub rule($target, $source, *@actions) {
    $target := $target;
    $source := nfp($source);
    my $rule := "{nfp($target)}: $source\n";
    for @actions -> $action {
        if $action ne '' {
            $rule := $rule ~ "\t$action\n";
        }
    }
    out($rule);
    $target;
}

sub nqp($prefix, $file, $stage, :$source=$prefix ~ '/' ~ $file ~ '.nqp', :$deps=[]) {
    my $path := stage_path($stage);
    my $mbc := $path ~ $file ~ '.moarvm';

    my $installed_pbc := 'gen/moar/stage2/' ~ $file ~ '.moarvm';

    nqp::unshift($deps, $source);

    $source := $source;

    rule($mbc, nqp::join(' ', $deps),
        make_parents($mbc),
        "\$(M_BUILD_RUNNER_BIN) --module-path=\$(JS_STAGE1) --target=mbc --output={nfp($mbc)} " ~ nfp($source),
        # HACK - workaround for not being able to supply multiple directories to --module-path
        make_parents($installed_pbc),
        "\$(CP) " ~ nfp("$mbc $installed_pbc")
    );
}

sub deps($target, *@deps) {
    $target := nfp($target);
    out("$target : {nfp(nqp::join(' ',@deps))}");
}

# TODO is the version regenerated as often as it should
sub combine(:$sources, :$stage, :$file, :$gen-version = 0) {

    my $target := stage_path($stage) ~ $file;
    my $version := stage_path($stage) ~ 'nqp-config.nqp';

    rule($target, $sources,
        make_parents($target),
        $gen-version ?? "\$(PERL5) \@script(gen-version.pl)@ \$(PREFIX) \$(NQP_LIB_DIR) > $version" !! '',
        "\$(PERL5) \@script(gen-cat.pl)@ js \@nfp($sources)@ {$gen-version ?? $version !! ''} > \@nfp($target)@"
    ); 
}

my $nqp-js-on-js := 'nqp-js-on-js';

sub cross-compile(:$stage, :$source, :$target, :$setting='NQPCORE', :$no-regex-lib=1, :$deps = []) {
    my $path := stage_path($stage);
    my $moarvm := $path ~ $target ~ '.moarvm';
    # todo dependency on compiler
    
    nqp::unshift($deps, $source);
    nqp::unshift($deps, '$(JS_STAGE1_COMPILER)');

    my $js := "$nqp-js-on-js/$target.js";


    rule($moarvm, nqp::join(' ', $deps), 
        make_parents($moarvm),
        make_parents($js),
	"\$(M_BUILD_RUNNER_BIN) --module-path " 
        ~ nfp("gen/js/stage1 src/vm/js/bin/cross-compile.nqp") 
        ~ " --setting={nfp($setting)} --target=mbc --js-output {nfp($js)} --output "
        ~ nfp($moarvm) ~ " {$no-regex-lib ?? "--no-regex-lib" !! ""} "
        ~ nfp($source) ~" > {nfp($js)}"
        );
}





comment("This is the JS Makefile - autogenerated by gen-js-makefile.nqp");

constant('JS_BUILD_DIR', '@js_build_dir@');
constant('JS_STAGE1', nfp('$(JS_BUILD_DIR)/stage1'));
constant('JS_STAGE2', nfp('$(JS_BUILD_DIR)/stage2'));
constant('JS_RUNNER', 'nqp-js$(BAT)');
constant('JS_CROSS_RUNNER', 'nqp-js-cross$(BAT)');

rule('$(JS_RUNNER)', '@script(gen-js-runner.pl)@','$(PERL5) @script(gen-js-runner.pl)@');
rule('$(JS_CROSS_RUNNER)', '@script(gen-js-cross-runner.pl)@','$(PERL5) @script(gen-js-cross-runner.pl)@ @nfp($(BASE_DIR)/$(M_BUILD_RUNNER))@');

out('js-runner-default: js-all');

my $QASTCompiler-combined := combine(:stage(1), :sources('src/vm/js/Utils.nqp src/vm/js/SerializeOnce.nqp src/vm/js/const_map.nqp src/vm/js/LoopInfo.nqp src/vm/js/ReturnInfo.nqp src/vm/js/BlockBarrier.nqp src/vm/js/DWIMYNameMangling.nqp src/vm/js/Chunk.nqp src/vm/js/Operations.nqp src/vm/js/RegexCompiler.nqp src/vm/js/Compiler.nqp'), :file('QASTCompiler.nqp'));


my $stage1-qast-compiler-moar := nqp('src/vm/js','QAST/Compiler',1, :source($QASTCompiler-combined));
my $stage1-hll-backend-moar := nqp('src/vm/js','HLL/Backend',1,:deps([$stage1-qast-compiler-moar]));

constant('JS_STAGE1_COMPILER',"$stage1-qast-compiler-moar $stage1-hll-backend-moar");


my $nqp-mo-combined := combine(:stage(2), :sources('$(NQP_MO_SOURCES)'), :file('$(NQP_MO_COMBINED)'));

my $nqp-mo-moarvm := cross-compile(:stage(2), :source($nqp-mo-combined), :target('nqpmo'), :setting('NULL'), :no-regex-lib(1));


my $nqpcore-combined := combine(:stage(2), :sources('$(CORE_SETTING_SOURCES)'), :file('$(CORE_SETTING_COMBINED).nqp'));

my $nqpcore-moarvm := cross-compile(:stage(2), :source($nqpcore-combined), :deps([$nqp-mo-moarvm]), :setting('NULL'), :target('NQPCORE.setting'));


my $QASTNode-combined := combine(:stage(2), :sources('$(QASTNODE_SOURCES)'), :file('$(QASTNODE_COMBINED)'));
my $QASTNode-moarvm := cross-compile(:stage(2), :source($QASTNode-combined), :target('QASTNode'), :setting('NQPCORE'), :no-regex-lib(1), :deps([$nqpcore-moarvm]));

my $QRegex-combined := combine(:stage(2), :sources('$(QREGEX_SOURCES)'), :file('$(QREGEX_COMBINED)'));
my $QRegex-moarvm := cross-compile(:stage(2), :source($QRegex-combined), :target('QRegex'), :setting('NQPCORE'), :no-regex-lib(1), :deps([$nqpcore-moarvm, $QASTNode-moarvm]));

my $sprintf-moarvm := cross-compile(:stage(2), :source('src/HLL/sprintf.nqp'), :target('sprintf'), :setting('NQPCORE'), :deps([$nqpcore-moarvm, $QRegex-moarvm]), :no-regex-lib(0)); 

deps('js-stage1-compiler', '$(JS_STAGE1_COMPILER)');

rule('js-test', 'js-cross gen/js/qregex.t $(JS_CROSS_RUNNER)',  
	"\$(PERL5) {nfp('src/vm/js/bin/run_tests.pl')}");

rule('js-test-bootstrapped', "js-bootstrap {nfp('gen/js/qregex.t')}",
	"\$(PERL5) {nfp('src/vm/js/bin/run_tests_bootstrapped.pl')}");

rule('gen/js/qregex.t', '@script(process-qregex-tests)@',
	"\$(M_BUILD_RUNNER_BIN) \@script(process-qregex-tests)@ > {nfp('gen/js/qregex.t')}");

rule('js-clean', '', 
    '$(RM_RF) ' ~ nfp('$(JS_BUILD_DIR)/stage1 $(JS_BUILD_DIR)/stage2 $(JS_BUILD_DIR)/qregex.t $(BASE_DIR)/package-lock.json'),
    '$(RM_L) ' ~ nfp('$(BASE_DIR)/node_modules/nqp-runtime'),
    '$(RM_RF) ' ~ nfp('$(BASE_DIR)/node_modules $(BASE_DIR)/src/vm/js/nqp-runtime/node_modules')
);

my $ModuleLoader := "$nqp-js-on-js/ModuleLoader.js";

deps("js-cross", 'm-all', 'js-stage1-compiler', $nqpcore-moarvm, $nqpcore-combined, $QASTNode-moarvm, $QRegex-moarvm, $sprintf-moarvm, $ModuleLoader, '$(JS_RUNNER)');

# Enforce the google coding standards
rule("js-lint", '',
	"gjslint --strict --max_line_length=200 --nojsdoc {nfp('src/vm/js/nqp-runtime/*.js')}");


my @install := <nqp-bootstrapped.js ModuleLoader.js package.json NQPCORE.setting.js NQPHLL.js nqpmo.js NQPP5QRegex.js NQPP6QRegex.js QAST/Compiler.js QAST.js QASTNode.js QRegex.js sprintf.js NQPCORE.setting.js.map NQPHLL.js.map nqpmo.js.map NQPP5QRegex.js.map NQPP6QRegex.js.map QAST/Compiler.js.map QAST.js.map QASTNode.js.map QRegex.js.map sprintf.js.map>;

my @cp_all;
for @install -> $file {
    my $source := nfp('nqp-js-on-js/' ~ $file);
    @cp_all.push("\$(CP) $source {nfp('$(DESTDIR)$(NQP_LIB_DIR)/nqp-js-on-js/' ~ $file)}");
}

rule('js-install', 'js-all',
  '$(MKPATH) $(DESTDIR)$(BIN_DIR)',
  '$(MKPATH) $(DESTDIR)$(NQP_LIB_DIR)',
  '$(MKPATH) ' ~ nfp('$(DESTDIR)$(NQP_LIB_DIR)/nqp-js-on-js'),
  '$(MKPATH) ' ~ nfp('$(DESTDIR)$(NQP_LIB_DIR)/nqp-js-on-js/QAST'),
  |@cp_all,
  '$(PERL5) @script(npm-install-or-link.pl)@ ' ~ nfp('$(DESTDIR)$(NQP_LIB_DIR)/nqp-js-on-js src/vm/js/nqp-runtime nqp-runtime @link@'),
  '$(PERL5) @script(install-js-runner.pl)@ "$(DESTDIR)" $(PREFIX) $(NQP_LIB_DIR)',
);

constant('JS_NQP_SOURCES', '$(COMMON_NQP_SOURCES)');



my $nqp-combined := combine(:stage(2), :sources('$(JS_NQP_SOURCES)'), :file('$(NQP_COMBINED)'), :gen-version(1));

constant('JS_HLL_SOURCES', nfp('src/vm/js/HLL/Backend.nqp') ~ ' $(COMMON_HLL_SOURCES)');

my $hll-combined := combine(:stage(2), :sources('$(JS_HLL_SOURCES)'), :file('$(HLL_COMBINED)'));



my $QAST-Compiler-moarvm := cross-compile(:stage(2), :source($QASTCompiler-combined), :target('QAST/Compiler'), :setting('NQPCORE'), :no-regex-lib(1), :deps([$nqpcore-moarvm, $QASTNode-moarvm]));


my $QAST-moarvm := cross-compile(:stage(2), :source('src/vm/js/QAST.nqp'), :target('QAST'), :setting('NQPCORE'), :no-regex-lib(1), :deps([$nqpcore-moarvm, $QAST-Compiler-moarvm]));


my $hll-moar := cross-compile(:stage(2), :source($hll-combined), :target('NQPHLL'), :setting('NQPCORE'), :no-regex-lib(1), :deps([$nqpcore-moarvm, $QAST-Compiler-moarvm, $QRegex-moarvm]));

my $p6qregex-combined := combine(:stage(2), :sources('$(P6QREGEX_SOURCES)'), :file('$(P6QREGEX_COMBINED)'));

my $p5qregex-combined := combine(:stage(2), :sources('$(P5QREGEX_SOURCES)'), :file('$(P5QREGEX_COMBINED)'));



my $NQPP5QRegex-moarvm := cross-compile(:stage(2), :source($p5qregex-combined), :target('NQPP5QRegex'), :setting('NQPCORE'), :no-regex-lib(1), :deps([$nqpcore-moarvm, $QAST-moarvm, $hll-moar, $QRegex-moarvm]));

my $NQPP6QRegex-moarvm := cross-compile(:stage(2), :source($p6qregex-combined), :target('NQPP6QRegex'), :setting('NQPCORE'), :no-regex-lib(1), :deps([$nqpcore-moarvm, $QAST-moarvm, $hll-moar, $QRegex-moarvm]));

my $nqp-bootstrapped := "$nqp-js-on-js/nqp-bootstrapped.js";


rule($ModuleLoader, "$nqpcore-moarvm src/vm/js/ModuleLoader.nqp \$(JS_STAGE1_COMPILER) \$(JS_CROSS_RUNNER)",
    ".@slash@\$(JS_CROSS_RUNNER) --setting=NULL --no-regex-lib --target=js --output $ModuleLoader src/vm/js/ModuleLoader.nqp"
);

rule($nqp-bootstrapped, "$QAST-moarvm $NQPP5QRegex-moarvm $NQPP6QRegex-moarvm $nqp-combined $QRegex-moarvm \$(JS_CROSS_RUNNER)",
    ".@slash@\$(JS_CROSS_RUNNER) --target=js --shebang $nqp-combined > $nqp-bootstrapped"
);

rule('js-runner-default', 'js-all',
  '$(CP) $(JS_RUNNER) nqp$(BAT)',
  '$(CHMOD) 755 nqp$(BAT)');

rule('js-runner-default-install', 'js-runner-default js-install',
  '$(CP) ' ~ nfp('$(DESTDIR)$(BIN_DIR)/$(JS_RUNNER) $(DESTDIR)$(BIN_DIR)/nqp$(BAT)'),
  '$(CHMOD) 755 ' ~ nfp('$(DESTDIR)$(BIN_DIR)/nqp$(BAT)'));

rule('js-deps', '',
  '$(PERL5) ' ~nfp('tools/build/npm-install-or-link.pl . src/vm/js/nqp-runtime nqp-runtime @link@'));

deps("js-all", "js-deps", "js-cross", $nqp-bootstrapped);

sub MAIN($program, $output-file?) {
    if $output-file {
        spurt($output-file, $out);
    } else {
        print($out);
    }
}
