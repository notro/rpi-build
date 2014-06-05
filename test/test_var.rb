require 'minitest/autorun'
require 'tmpdir'
require_relative '../var.rb'

def workdir(file=nil)
  file ? File.join($tmpdir, file) : $tmpdir
end

def debug(*args)
end

class TestVar < MiniTest::Unit::TestCase
  def setup
    ENV.delete 'testvar'
    VAR.delete_default 'testvar'
    $tmpdir = Dir.mktmpdir
  end

  def teardown
    `rm -r #{$tmpdir}`
    $tmpdir = nil
  end

  def test_get
    assert_nil VAR['testvar']
    ENV['testvar'] = 'val'
    assert_equal VAR['testvar'], 'val'
    ENV.delete 'testvar'
    assert_nil VAR['testvar']
  end

  def test_set
    VAR['testvar'] = 'val'
    assert_equal VAR['testvar'], 'val'
    ENV.delete 'testvar'
    assert_nil ENV['testvar']
    assert_equal VAR['testvar'], 'val'
  end

  def test_delete
    VAR['testvar'] = 'val'
    assert_equal VAR['testvar'], 'val'
    VAR.delete 'testvar'
    assert_nil VAR['testvar']
  end

  def test_default
    VAR.default('testvar') { 'blockval' }
    assert_nil ENV['testvar']
    assert_equal VAR['testvar'], 'blockval'
    VAR.delete_default 'testvar'
    ENV.delete 'testvar'
    assert_nil ENV['testvar']
    assert_nil VAR['testvar']
  end

  def test_store
    assert_nil VAR['testvar']
    VAR.store 'testvar'
    assert_nil VAR['testvar']

    ENV['testvar'] = 'val'
    assert_equal VAR['testvar'], 'val'
    VAR.store 'testvar'
    ENV.delete 'testvar'
    assert_nil ENV['testvar']
    assert_equal VAR['testvar'], 'val'
    VAR.delete 'testvar'

    VAR.default('testvar') { 'blockval' }
    VAR.store 'testvar'
    ENV.delete 'testvar'
    assert_nil ENV['testvar']
    assert_equal VAR['testvar'], 'blockval'
  end

  def test_key?
    assert !VAR.key?('testvar')

    ENV['testvar'] = 'val'
    assert VAR.key?('testvar')
    ENV.delete 'testvar'
    assert !VAR.key?('testvar')

    VAR['testvar'] = 'val'
    assert VAR.key?('testvar')
    VAR.delete 'testvar'
    assert !VAR.key?('testvar')

    VAR.default('testvar') { 'blockval' }
    assert VAR.key?('testvar')
    VAR.delete_default 'testvar'
    assert !VAR.key?('testvar')
  end

  def test_load_all
    VAR['testvar'] = 'load_all'
    ENV.delete 'testvar'
    assert_nil ENV['testvar']
    VAR.load_all
    assert_equal ENV['testvar'], 'load_all'
  end
end
