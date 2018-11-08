# CSV Normalization

You will want ruby 2.4 or greater to handle uppercasing non ASCII name
columns. See https://bugs.ruby-lang.org/issues/10085

It appears that ruby 2.3 is provided for both macOS 10.13 and Ubuntu
16.04 LTS.

You have a few options.

## Running the code

### Docker

If you have docker installed, the easiest thing to do would be:

    docker run -i --rm=true \
      -v $PWD/lib/csv_normalizer.rb:/csv_normalizer.rb \
      ruby:2.4.3-slim-stretch \
      ruby -E UTF-8:UTF-8 csv_normalizer.rb \
      < /path/to/your/file.csv
      
### Native ruby

If you want to run a ruby version prior to 2.4, you can do so, but a
warning will be generated.

    ruby -E UTF-8:UTF-8 \
      lib/csv_normalizer.rb \
      < /path/to/your/file.csv

### macOS
You could use [rvm](https://rvm.io/) and/or
[rbenv](https://github.com/rbenv/rbenv) to install ruby 2.4 on macOS

### Ubuntu
You could use the [Brightbox Ubuntu packages](https://www.brightbox.com/docs/ruby/ubuntu/) to install ruby
2.4 on Ubuntu.

## Tests

### Docker

To run the tests, do:

    docker run -i --rm=true \
      -v $PWD:/csv \
      ruby:2.4.3-slim-stretch \
      ruby -E UTF-8:UTF-8 -I/csv/lib /csv/test/test_csv_normalizer.rb

### Native Ruby

    ruby -Ilib test/test_csv_normalizer.rb

