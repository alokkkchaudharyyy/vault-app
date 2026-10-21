package dev.atharv.vault

import android.content.Context
import android.content.Intent
import androidx.health.connect.client.HealthConnectClient
import androidx.health.connect.client.PermissionController
import androidx.health.connect.client.permission.HealthPermission
import androidx.health.connect.client.records.SleepSessionRecord
import androidx.health.connect.client.records.StepsRecord
import androidx.health.connect.client.request.AggregateGroupByPeriodRequest
import androidx.health.connect.client.request.ReadRecordsRequest
import androidx.health.connect.client.time.TimeRangeFilter
import java.time.Duration
import java.time.LocalDate
import java.time.Period
import java.time.ZoneId

/**
 * Steps and sleep from Health Connect, where Samsung Health, Google Fit and
 * watches put them. Read only.
 */
object Health {
    val permissions = setOf(
        HealthPermission.getReadPermission(StepsRecord::class),
        HealthPermission.getReadPermission(SleepSessionRecord::class),
    )

    fun available(context: Context) =
        HealthConnectClient.getSdkStatus(context) == HealthConnectClient.SDK_AVAILABLE

    private fun client(context: Context) = HealthConnectClient.getOrCreate(context)

    suspend fun granted(context: Context): Set<String> =
        if (available(context)) client(context).permissionController.getGrantedPermissions() else emptySet()

    /** Connected when at least one of steps and sleep may be read. */
    suspend fun hasAccess(context: Context): Boolean = granted(context).any { it in permissions }

    /** Health Connect's own settings, where access and sources are managed. */
    fun settingsIntent(): Intent = Intent(HealthConnectClient.ACTION_HEALTH_CONNECT_SETTINGS)

    /** The screen that asks for [permissions]. */
    fun requestIntent(context: Context): Intent =
        PermissionController.createRequestPermissionResultContract().createIntent(context, permissions)

    /**
     * One map per day in [from]..[to] (YYYY-MM-DD) that has data: {date,
     * steps?, sleep? (minutes), sleepDetail? ("01:30-09:00")}. Sleep on a day
     * is the longest session ending that day.
     */
    suspend fun days(context: Context, from: String, to: String): List<Map<String, Any>> {
        val zone = ZoneId.systemDefault()
        val start = LocalDate.parse(from).atStartOfDay()
        val end = LocalDate.parse(to).plusDays(1).atStartOfDay()
        val out = sortedMapOf<String, MutableMap<String, Any>>()
        val c = client(context)
        val granted = granted(context)

        if (HealthPermission.getReadPermission(StepsRecord::class) in granted) for (slice in c.aggregateGroupByPeriod(
            AggregateGroupByPeriodRequest(
                metrics = setOf(StepsRecord.COUNT_TOTAL),
                timeRangeFilter = TimeRangeFilter.between(start, end),
                timeRangeSlicer = Period.ofDays(1),
            )
        )) {
            val steps = slice.result[StepsRecord.COUNT_TOTAL] ?: continue
            out.getOrPut(slice.startTime.toLocalDate().toString()) { mutableMapOf() }["steps"] = steps
        }

        val sleeps = if (HealthPermission.getReadPermission(SleepSessionRecord::class) !in granted) emptyList() else c.readRecords(
            ReadRecordsRequest(
                SleepSessionRecord::class,
                TimeRangeFilter.between(start.minusDays(1).atZone(zone).toInstant(), end.atZone(zone).toInstant()),
            )
        ).records
        for (r in sleeps) {
            val bed = r.startTime.atZone(zone)
            val wake = r.endTime.atZone(zone)
            val day = wake.toLocalDate().toString()
            if (day < from || day > to) continue
            val minutes = Duration.between(r.startTime, r.endTime).toMinutes()
            val m = out.getOrPut(day) { mutableMapOf() }
            if ((m["sleep"] as? Long ?: 0L) < minutes) {
                m["sleep"] = minutes
                m["sleepDetail"] = "%02d:%02d-%02d:%02d".format(bed.hour, bed.minute, wake.hour, wake.minute)
            }
        }
        return out.map { (date, m) -> m + ("date" to date) }
    }
}
