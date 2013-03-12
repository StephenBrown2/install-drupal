Drupal Install Script
---------------------

This is basically just a wrapper around drush site-install, which asks you for all the necessary
information before running the install script, and checks several things not included, such as a
solr installation and adding new users (aside from the default 'admin') right after install.
