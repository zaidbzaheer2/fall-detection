import 'package:mailer/mailer.dart';
import 'package:mailer/smtp_server.dart';

class EmailService {
  static const String _senderEmail = '';
  static const String _appPassword = '';
  
  /// Send email alert to emergency contact
  static Future<bool> sendFallAlert(String recipientEmail, String userName) async {
    try {
      if (_appPassword == 'your_app_password_here') {
        print('⚠️ Email service not configured. Please set _senderEmail and _appPassword in email_service.dart');
        return false;
      }
      
      final smtpServer = gmail(_senderEmail, _appPassword);
      
      // Create the email message
      final message = Message()
        ..from = Address(_senderEmail, 'Fall Detection Alert System')
        ..recipients.add(recipientEmail)
        ..subject = 'FALL ALERT: $userName may have fallen'
        ..html = _buildEmailHtml(userName);
      
      // Send the email
      await send(message, smtpServer);
      print('Fall alert email sent successfully to $recipientEmail');
      return true;
    } catch (e) {
      print('Error sending email: $e');
      return false;
    }
  }
  
  static String _buildEmailHtml(String userName) {
    return '''
    <html>
      <head>
        <style>
          body { font-family: Arial, sans-serif; background-color: #f5f5f5; }
          .container { max-width: 600px; margin: 0 auto; background-color: white; padding: 20px; border-radius: 8px; box-shadow: 0 2px 4px rgba(0,0,0,0.1); }
          .header { background-color: #d32f2f; color: white; padding: 20px; border-radius: 4px; text-align: center; margin-bottom: 20px; }
          .header h1 { margin: 0; font-size: 24px; }
          .content { color: #333; line-height: 1.6; }
          .alert-info { background-color: #fff3cd; border-left: 4px solid #ffc107; padding: 12px; margin: 15px 0; border-radius: 4px; }
          .footer { margin-top: 20px; padding-top: 20px; border-top: 1px solid #eee; font-size: 12px; color: #666; text-align: center; }
        </style>
      </head>
      <body>
        <div class="container">
          <div class="header">
            <h1>⚠️ FALL DETECTED!</h1>
          </div>
          <div class="content">
            <p>A fall has been detected for <strong>$userName</strong>.</p>
            <div class="alert-info">
              <strong>Alert Details:</strong><br>
              A potential fall was detected at <strong>${DateTime.now().toString()}</strong>.
            </div>
            <p><strong>Recommended Actions:</strong></p>
            <ul>
              <li>Contact $userName immediately</li>
              <li>Check on their location and condition</li>
              <li>Call emergency services if necessary</li>
            </ul>
          </div>
          <div class="footer">
            <p>This is an automated alert from the Fall Detection System.</p>
          </div>
        </div>
      </body>
    </html>
    ''';
  }
}
