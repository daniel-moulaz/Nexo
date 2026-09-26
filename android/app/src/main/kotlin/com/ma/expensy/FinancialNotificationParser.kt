package com.ma.expensy

import java.text.Normalizer
import java.util.Locale
import java.security.MessageDigest

/** Pure parser: rejects ambiguity; never retains the source notification. */
object FinancialNotificationParser {
    data class Suggestion(val cents: Long, val description: String, val kind: String, val medium: String)
    fun normalize(text: String): String = Normalizer.normalize(text, Normalizer.Form.NFD)
        .replace(Regex("\\p{M}+"), "").lowercase(Locale.ROOT).replace(Regex("\\s+"), " ").trim()
    fun fingerprint(app: String, key: String, time: Long, item: Suggestion): String =
        MessageDigest.getInstance("SHA-256").digest(
            "$app|$key|${time / 60000}|${item.cents}|${normalize(item.description)}|${item.kind}".toByteArray())
            .joinToString("") { "%02x".format(it) }
    fun parse(raw: String): Suggestion? {
        if (raw.length > 3000) return null
        val text = normalize(raw)
        if (Regex("\\b(recusad[ao]|negad[ao]|tentativa|agendad[ao]|agendamento|oferta|promocao|codigo|senha|token|otp|fatura|limite|saldo|solicitacao|pendente|cancelad[ao])\\b").containsMatchIn(text)) return null
        val kind = when {
            Regex("\\b(estorno|reembolso) (recebido|realizado|aprovado|de)\\b").containsMatchIn(text) -> "refund"
            Regex("\\bpix (recebido|recebida)\\b").containsMatchIn(text) -> "income"
            Regex("\\bpix (enviado|realizado)\\b").containsMatchIn(text) -> "expense"
            Regex("\\btransferencia (recebida|realizada|enviada)\\b").containsMatchIn(text) -> "transfer"
            Regex("\\b(compra (aprovada|realizada|no debito|no credito)|pagamento (aprovado|realizado|efetuado))\\b").containsMatchIn(text) -> "expense"
            else -> return null
        }
        val amounts = Regex("(?<![\\d.,])(?:r\\$\\s*)?(\\d{1,3}(?:\\.\\d{3})*,\\d{2}|\\d+,\\d{2})(?![\\d.,])")
            .findAll(text).map { it.groupValues[1] }.distinct().toList()
        if (amounts.size != 1) return null
        val cents = amounts.single().replace(".", "").replace(",", "").toLongOrNull() ?: return null
        if (cents <= 0 || cents > 100000000000L) return null
        val merchant = Regex("(?:\\bem |\\bpara |\\bde )([\\p{L}][\\p{L}0-9 *._-]{1,79})", RegexOption.IGNORE_CASE)
            .findAll(raw).lastOrNull()?.groupValues?.get(1)?.trim()?.take(80)
        val description = merchant ?: when(kind) {
            "income" -> "Pix recebido"
            "transfer" -> "Transferência"
            "refund" -> "Estorno / reembolso"
            else -> if (text.contains("pix")) "Pix enviado" else "Compra / pagamento"
        }
        val medium = when { text.contains("credito") -> "credit"; text.contains("debito") || text.contains("pix") -> "bank"; else -> "unknown" }
        return Suggestion(cents, description, kind, medium)
    }
}
