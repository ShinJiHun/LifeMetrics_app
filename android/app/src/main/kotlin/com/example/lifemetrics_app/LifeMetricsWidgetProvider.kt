package com.example.lifemetrics_app

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider

// 홈 화면 위젯: 오늘 걸음 · 이번 주 라이딩 · 최근 체중.
// 숫자는 Dart(HomeWidgetService)가 모아 widgetData 에 넣어 두고, 여기서는 그리기만 함. 누르면 앱 열기
class LifeMetricsWidgetProvider : HomeWidgetProvider() {
  override fun onUpdate(
      context: Context,
      appWidgetManager: AppWidgetManager,
      appWidgetIds: IntArray,
      widgetData: SharedPreferences,
  ) {
    appWidgetIds.forEach { widgetId ->
      val views =
          RemoteViews(context.packageName, R.layout.lifemetrics_widget).apply {
            setTextViewText(R.id.widget_steps, widgetData.getString("steps", null) ?: "-")
            setTextViewText(R.id.widget_ride, widgetData.getString("ride", null) ?: "-")
            setTextViewText(R.id.widget_weight, widgetData.getString("weight", null) ?: "-")
            setTextViewText(
                R.id.widget_updated,
                widgetData.getString("updated", null) ?: "앱을 열면 갱신돼요",
            )
            setOnClickPendingIntent(
                R.id.widget_root,
                HomeWidgetLaunchIntent.getActivity(context, MainActivity::class.java),
            )
          }
      appWidgetManager.updateAppWidget(widgetId, views)
    }
  }
}
