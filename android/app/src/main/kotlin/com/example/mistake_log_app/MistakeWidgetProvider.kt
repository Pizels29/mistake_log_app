package com.example.mistake_log_app

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.content.Intent
import android.graphics.BitmapFactory
import android.widget.RemoteViews
import org.json.JSONArray
import java.text.SimpleDateFormat
import java.util.TimeZone
import java.util.Calendar
import java.util.Locale

class MistakeWidgetProvider : AppWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray
    ) {
        appWidgetIds.forEach { id ->
            appWidgetManager.updateAppWidget(id, buildWidget(context))
        }
    }

    override fun onAppWidgetOptionsChanged(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetId: Int,
        newOptions: android.os.Bundle
    ) {
        appWidgetManager.updateAppWidget(appWidgetId, buildWidget(context))
    }

    private fun buildWidget(context: Context): RemoteViews {
        val views = RemoteViews(context.packageName, R.layout.mistake_widget)
        val preferences =
            context.getSharedPreferences("HomeWidgetPreferences", Context.MODE_PRIVATE)
        val cycle = preferences.getString("mistake_cycle", null)
        val anchor = preferences.getString("mistake_cycle_anchor", null)
        val mistakes = cycle?.let(::JSONArray) ?: JSONArray()

        if (mistakes.length() == 0) {
            views.setTextViewText(R.id.widget_class, "MISTAKE LOG")
            views.setTextViewText(R.id.widget_description, "Add a mistake to start your daily review.")
            views.setTextViewText(R.id.widget_tags, "")
        } else {
            val anchorDate = anchor?.let(::parseDate) ?: today()
            val days = (utcDay(today()) - utcDay(anchorDate)) / DAY_MILLIS
            val count = mistakes.length().toLong()
            val index = ((days % count + count) % count).toInt()
            val mistake = mistakes.getJSONObject(index)
            views.setTextViewText(R.id.widget_class, mistake.optString("className", "Mistake Log"))
            views.setTextViewText(
                R.id.widget_description,
                mistake.optString("description", "Review today's mistake.")
            )
            views.setTextViewText(R.id.widget_tags, mistake.optString("tags", ""))
            val photoPath = mistake.optString("photoPath")
            if (photoPath.isNotEmpty()) {
                val bitmap = decodeWidgetPhoto(photoPath)
                if (bitmap != null) {
                    views.setImageViewBitmap(R.id.widget_photo, bitmap)
                    views.setViewVisibility(R.id.widget_photo, android.view.View.VISIBLE)
                } else {
                    views.setViewVisibility(R.id.widget_photo, android.view.View.GONE)
                }
            } else {
                views.setViewVisibility(R.id.widget_photo, android.view.View.GONE)
            }
        }

        val launchIntent = context.packageManager.getLaunchIntentForPackage(context.packageName)
        if (launchIntent != null) {
            val pendingIntent = PendingIntent.getActivity(
                context,
                0,
                launchIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            views.setOnClickPendingIntent(R.id.widget_root, pendingIntent)
        }
        return views
    }

    private fun decodeWidgetPhoto(path: String): android.graphics.Bitmap? {
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeFile(path, bounds)
        if (bounds.outWidth <= 0 || bounds.outHeight <= 0) return null

        val sampleSize = maxOf(
            1,
            minOf(bounds.outWidth / 900, bounds.outHeight / 500)
        )
        return BitmapFactory.decodeFile(
            path,
            BitmapFactory.Options().apply { inSampleSize = sampleSize }
        )
    }

    private fun parseDate(value: String): Calendar =
        Calendar.getInstance().apply {
            val parsed = SimpleDateFormat("yyyy-MM-dd", Locale.US).parse(value)
            if (parsed != null) time = parsed
        }

    private fun today(): Calendar = Calendar.getInstance().apply {
        set(Calendar.HOUR_OF_DAY, 0)
        set(Calendar.MINUTE, 0)
        set(Calendar.SECOND, 0)
        set(Calendar.MILLISECOND, 0)
    }

    private fun utcDay(date: Calendar): Long =
        Calendar.getInstance(TimeZone.getTimeZone("UTC")).apply {
            clear()
            set(date.get(Calendar.YEAR), date.get(Calendar.MONTH), date.get(Calendar.DAY_OF_MONTH))
        }.timeInMillis

    companion object {
        private const val DAY_MILLIS = 24 * 60 * 60 * 1000L
    }
}
