/// Messages shown to users when something goes wrong.
///
/// Users never see raw error text (stack traces, API errors, model names).
/// The real error is logged on the server; the user gets a short, friendly
/// message telling them what to do next.
abstract class UserMessages {
  static const String somethingWentWrong =
      "Sorry, something went wrong on my side. 🙏\n\n"
      "Please try again in a moment. If it keeps happening, type *Menu* to start over.";

  static const String receiptFailed =
      "Sorry, I couldn't make that receipt. 🙏\n\n"
      "Please try sending the details again, for example:\n"
      "_2 bags of rice at 45,000 for Ada_\n\n"
      "Or type *Create Receipt* for help.";
}
