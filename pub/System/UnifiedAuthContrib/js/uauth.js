;(function ($, document, window, undefined) {
  $(document).ready(function() {
    $('.uauth .social_provider').on('click', function() {
      var provider = $(this).attr('name');
      $('input[name="uauth_provider"]').val(provider);
      $('input[name="uauth_external"]').val(1);
    });
  });
}(jQuery, document, window, undefined));
