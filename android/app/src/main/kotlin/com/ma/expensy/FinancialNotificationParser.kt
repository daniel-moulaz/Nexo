package com.ma.expensy

import java.text.Normalizer
import java.util.Locale
import java.security.MessageDigest

/** Local semantic patterns, not a claim that a bank's changing copy is an API. */
object FinancialNotificationParser {
    data class Suggestion(val cents: Long, val description: String, val kind: String, val medium: String,
        val confidence: String = "high", val patternId: String = "explicit_event")
    data class ParserResult(val suggestion: Suggestion?, val reason: String)
    data class NotificationPattern(val id: String, val kind: String, val regex: Regex, val confidence: String = "high")
    private val patterns = listOf(
        NotificationPattern("refund", "refund", Regex("\\b(estorno|reembolso) (recebido|realizado|aprovado|de)\\b")),
        NotificationPattern("pix_in", "income", Regex("\\b(pix recebid[oa]|recebeu (um )?pix|recebimento de pix)\\b")),
        NotificationPattern("pix_out", "expense", Regex("\\b(pix (enviado|realizado)|voce enviou (um )?pix)\\b")),
        NotificationPattern("transfer", "transfer", Regex("\\btransferencia (recebida|realizada|enviada)\\b"), "medium"),
        NotificationPattern("purchase", "expense", Regex("\\b(compra (aprovada|realizada|no debito|no credito)|compra (de |no valor de )?<valor> (foi )?(aprovada|realizada))\\b")),
        NotificationPattern("payment", "expense", Regex("\\bpagamento (aprovado|realizado|efetuado)\\b"), "medium")
    )
    private val money = Regex("(?<![\\d.,])(?:r\\$\\s*)?(\\d{1,3}(?:\\.\\d{3})*,\\d{2}|\\d+,\\d{2})(?![\\d.,])")
    fun normalize(text: String): String = Normalizer.normalize(text, Normalizer.Form.NFD)
        .replace(Regex("\\p{M}+"), "").lowercase(Locale.ROOT).replace(Regex("\\s+"), " ").trim()
    fun fingerprint(app: String, key: String, time: Long, item: Suggestion): String =
        MessageDigest.getInstance("SHA-256").digest(
            "$app|$key|${time / 60000}|${item.cents}|${normalize(item.description)}|${item.kind}".toByteArray())
            .joinToString("") { "%02x".format(it) }
    fun parse(raw: String): Suggestion? = analyze(raw).suggestion
    fun analyzeParts(title: String?, body: String?): ParserResult {
        // Expanded Android templates often repeat the title verbatim.
        val t = title.orEmpty().trim(); val b = body.orEmpty().trim()
        return analyze(if (normalize(b).startsWith(normalize(t))) b else "$t $b")
    }
    fun analyze(raw: String): ParserResult {
        fun reject(reason: String) = ParserResult(null, reason)
        if (raw.length > 3000) return reject("unrecognized")
        val text = normalize(raw)
        if (Regex("\\b(usd|eur|gbp|dolar|dolares|euros)\\b|us\\$|€|£|[-−]\\s*(r\\$\\s*)?\\d[\\d.,]*,\\d{2}").containsMatchIn(text)) return reject("unrecognized")
        if (Regex("\\b(codigo|senha|token|otp|autenticacao|verificacao)\\b").containsMatchIn(text)) return reject("sensitive")
        if (Regex("\\b(nao|recusad[ao]|negad[ao]|tentativa|agendad[ao]|agendamento|oferta|promocao|solicitacao|pendente|cancelad[ao]|confirme|reconhece|reconhecer|suspeita)\\b").containsMatchIn(text)) return reject("not_financial")
        if (Regex("\\b(fatura|limite|saldo)\\b").containsMatchIn(text)) return reject("balance_or_invoice")
        val amounts = money.findAll(text).toList()
        if (amounts.size > 1) return reject("multiple_amounts")
        if (amounts.size != 1) return reject("unrecognized")
        val cents = amounts.single().groupValues[1].replace(".", "").replace(",", "").toLongOrNull()
            ?: return reject("unrecognized")
        if (cents <= 0 || cents > 100000000000L) return reject("unrecognized")
        val eventText = money.replace(text, "<valor>")
        val matches = patterns.filter { it.regex.containsMatchIn(eventText) }
        if (matches.map { it.kind }.distinct().size != 1) return reject("unrecognized")
        val pattern = matches.first()
        // Keep only a short merchant after 'em'; never retain a raw excerpt or Pix recipient.
        val candidate = Regex("\\bem ([\\p{L}][\\p{L}0-9 *._-]{1,59})", RegexOption.IGNORE_CASE)
            .find(raw)?.groupValues?.get(1)?.trim()
        val merchant = candidate?.takeIf {
            !Regex("\\d{4,}|\\b(cartao|credito|debito|valor|conta|dia)\\b").containsMatchIn(normalize(it))
        }
        val description = if (pattern.kind == "expense" && merchant != null) merchant else when(pattern.kind) {
            "income" -> "Pix recebido"
            "transfer" -> "Transferência para revisar"
            "refund" -> "Estorno / reembolso"
            else -> if (text.contains("pix")) "Pix enviado" else "Compra / pagamento"
        }
        val credit = Regex("\\bcredito\\b").containsMatchIn(text)
        val bank = Regex("\\b(debito|pix)\\b").containsMatchIn(text)
        val medium = when { credit && bank -> "unknown"; credit -> "credit"; bank -> "bank"; else -> "unknown" }
        return ParserResult(Suggestion(cents, description, pattern.kind, medium, pattern.confidence, pattern.id), "created")
    }
}
