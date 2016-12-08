;(function ($, document, window, undefined) {
  $(document).ready(function() {
    $('.uauth button').on('click', function() {
      var provider = $(this).attr('name');
      $('input[name="uauth_provider"]').val(provider);
      $('input[name="uauth_initial"]').val(1);
    });
  });
}(jQuery, document, window, undefined));
