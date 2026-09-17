interface InsightCardProps {
  food: string;
  symptom: string;
  confidence: number;
  occurrences: number;
}

const InsightCard = ({ food, symptom, confidence, occurrences }: InsightCardProps) => {
  // Determine reliability based on sample size
  const getSampleSizeReliability = () => {
    if (occurrences >= 5) return "High reliability";
    if (occurrences >= 3) return "Moderate reliability";
    return "Low reliability - more data needed";
  };

  // Get appropriate icon and styles based on confidence and sample size
  const getIconColor = () => {
    if (occurrences < 3) return 'bg-blue-100 text-blue-500'; // Not enough data yet
    if (confidence >= 70) return 'bg-red-100 text-red-500';
    if (confidence >= 40) return 'bg-yellow-100 text-yellow-500';
    return 'bg-blue-100 text-blue-500';
  };

  // Get confidence bar color
  const getConfidenceBarColor = () => {
    if (occurrences < 3) return 'bg-blue-500'; // Not enough data yet
    if (confidence >= 70) return 'bg-red-500';
    if (confidence >= 40) return 'bg-yellow-500';
    return 'bg-blue-500';
  };

  return (
    <div className="bg-white rounded-lg shadow-sm p-4">
      <div className="flex items-start">
        <div className={`w-10 h-10 rounded-full flex items-center justify-center mr-3 mt-1 ${getIconColor()}`}>
          <svg xmlns="http://www.w3.org/2000/svg" className="h-5 w-5" viewBox="0 0 20 20" fill="currentColor">
            <path fillRule="evenodd" d="M8.257 3.099c.765-1.36 2.722-1.36 3.486 0l5.58 9.92c.75 1.334-.213 2.98-1.742 2.98H4.42c-1.53 0-2.493-1.646-1.743-2.98l5.58-9.92zM11 13a1 1 0 11-2 0 1 1 0 012 0zm-1-8a1 1 0 00-1 1v3a1 1 0 002 0V6a1 1 0 00-1-1z" clipRule="evenodd" />
          </svg>
        </div>
        <div>
          <p className="font-medium text-navy">{food} may be linked to your {symptom.toLowerCase()}</p>
          <div className="text-gray-500 text-sm mt-1">
            <div className="flex items-center justify-between mt-1 mb-1">
              <span>Confidence:</span>
              <span className="font-medium">{confidence}%</span>
            </div>
            <div className="w-full bg-gray-200 rounded-full h-1.5">
              <div 
                className={`h-1.5 rounded-full ${getConfidenceBarColor()}`} 
                style={{width: `${confidence}%`}}
              ></div>
            </div>
            <div className="flex justify-between mt-2">
              <p>Based on {occurrences} occurrence{occurrences !== 1 ? 's' : ''}</p>
              <span className={`text-xs px-2 py-1 rounded-full ${
                occurrences >= 5 ? 'bg-green-100 text-green-700' : 
                occurrences >= 3 ? 'bg-yellow-100 text-yellow-700' : 
                'bg-blue-100 text-blue-700'
              }`}>
                {getSampleSizeReliability()}
              </span>
            </div>
          </div>
        </div>
      </div>
    </div>
  );
};

export default InsightCard;
