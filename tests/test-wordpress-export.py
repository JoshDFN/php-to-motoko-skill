#!/usr/bin/env python3
"""Exercise documented WordPress exports against isolated API/context stand-ins."""
from pathlib import Path
import re
import subprocess
import tempfile
import textwrap

skill = Path(__file__).resolve().parents[1] / 'skills/migrating-php-apps'
source = (skill / 'references/frameworks.md').read_text()
blocks = re.findall(r'^\s*```php\n([\s\S]*?)^\s*```', source, re.M)
assert len(blocks) == 3, 'expected shared, WordPress and Drupal PHP examples'

stub = r'''<?php
namespace Elementor {
  class Frontend {
    public function get_builder_content_for_display($id, $css) {
      // Match Elementor's real recursion guard for a currently established post.
      if (\get_the_ID() === $id) return '';
      return $this->get_builder_content($id, $css);
    }
    public function get_builder_content($id, $css) {
      if (\get_the_ID() !== $id || !$css) throw new \RuntimeException('missing source context or CSS request');
      return $GLOBALS['mode'] === 'builder-empty' ? '' : '<h2>Welkom bij de gemeente</h2>';
    }
  }
  class Plugin { public static $instance; }
}
namespace {
  $mode = $argv[3]; $GLOBALS['mode'] = $mode;
  define('ABSPATH', $argv[1]);
  putenv('MIGRATION_WEB_ROOTS=' . ABSPATH); putenv('MIGRATION_EXPORT_DIR=' . $argv[2]);
  putenv('MIGRATION_PUBLIC_POST_IDS=12'); putenv('MIGRATION_USER_IDS=4');
  \Elementor\Plugin::$instance = (object) ['frontend' => new \Elementor\Frontend()];
  $GLOBALS['post'] = (object) ['ID' => 99];
  function get_the_ID() { return $GLOBALS['post']->ID; }
  function get_current_user_id() { return $GLOBALS['mode'] === 'privileged' ? 1 : 0; }
  function get_post($id) { return (object) ['ID' => $id, 'post_type' => 'page', 'post_status' => 'publish', 'post_password' => $GLOBALS['mode'] === 'protected' ? 'secret' : '', 'post_content' => 'source', 'post_title' => 'Title', 'post_modified_gmt' => '2026-10-21 00:00:00', 'post_author' => 4]; }
  function setup_postdata($p) { if (get_the_ID() !== 12) throw new \RuntimeException('post context missing'); return true; }
  function get_permalink($p) { return 'https://example.test/parent/child/?lang=fr'; }
  function apply_filters($name, $value) { return 'context:' . get_the_ID(); }
  function get_current_blog_id() { return 2; }
  function home_url($path) { return 'https://example.test' . $path; }
  function pll_get_post_language($id) { return 'fr'; }
  function pll_get_post_translations($id) { return ['fr' => 12, 'en' => 13]; }
  function get_post_meta($id, $key, $single) { return $key === '_elementor_edit_mode' && str_starts_with($GLOBALS['mode'], 'builder') ? 'builder' : ''; }
  function wp_reset_postdata() {}
  function get_userdata($id) { return (object) ['user_email' => 'person@example.test', 'display_name' => 'Person', 'roles' => ['editor', 'custom']]; }
  $failures = ['builder-empty' => 'Builder snapshot', 'protected' => 'not eligible', 'privileged' => 'without a privileged'];
  try {
    require __DIR__ . '/wp-export.php';
    if (isset($failures[$mode])) throw new \LogicException('unsafe export succeeded');
    $row = json_decode(file_get_contents($argv[2] . '/content.jsonl'), true, flags: JSON_THROW_ON_ERROR);
    $user = json_decode(file_get_contents($argv[2] . '/users.jsonl'), true, flags: JSON_THROW_ON_ERROR);
    $expected = $mode === 'builder' ? '<h2>Welkom bij de gemeente</h2>' : 'context:12';
    if ($row['bodyHtml'] !== $expected || $row['route'] !== '/parent/child/?lang=fr' || $user['sourceRoles'] !== ['editor', 'custom']) throw new \LogicException('exported data mismatch');
  } catch (\RuntimeException $e) {
    if (!isset($failures[$mode]) || !str_contains($e->getMessage(), $failures[$mode]) || file_exists($argv[2] . '/content.jsonl')) throw $e;
  }
  if (get_the_ID() !== 99) throw new \LogicException('source context not restored');
  echo $mode, ": pass\n";
}
'''

with tempfile.TemporaryDirectory(prefix='wp-export-context-') as directory:
    root = Path(directory)
    for name, code in zip(('export-support.php', 'wp-export.php'), blocks):
        (root / name).write_text(textwrap.dedent(code).rstrip() + '\n')
        subprocess.run(['php', '-l', str(root / name)], check=True)
    harness = root / 'context-check.php'
    harness.write_text(stub)
    web = root / 'web'
    web.mkdir()
    for mode in ('plain', 'builder', 'builder-empty', 'protected', 'privileged'):
        subprocess.run(['php', str(harness), str(web), str(root / ('export-' + mode)), mode], check=True)
print('WordPress exporter context: 5 passed; synthetic API stand-ins only')
